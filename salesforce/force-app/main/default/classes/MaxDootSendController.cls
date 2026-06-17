/**
 * Apex controller backing the MaxDoot inbox and conversation LWCs:
 * lists conversations, loads a thread, sends outbound messages via heydoot, and
 * clears unread counts.
 */
public with sharing class MaxDootSendController {

    @AuraEnabled(cacheable=true)
    public static List<Conversation__c> getOpenConversations(String statusFilter, String ownerScope) {
        String status = String.isBlank(statusFilter) ? 'Open' : statusFilter;
        Id me = UserInfo.getUserId();
        String scope = String.isBlank(ownerScope) ? 'Mine' : ownerScope;

        // The record Owner drives sharing (OWD Private + role hierarchy), so ownership
        // filtering keys off OwnerId. Unassigned cold inbound is owned by the queue.
        String filter = 'Status__c = :status';
        if (scope == 'Mine') {
            filter += ' AND OwnerId = :me';
        } else if (scope == 'Unassigned') {
            filter += ' AND Owner.Type = \'Queue\'';
        }
        // 'All' applies no owner filter; OWD Private already scopes to accessible rows
        // (own + claimed + subordinates' via role hierarchy for managers).

        String soql =
            'SELECT Id, Name, Customer_Number__c, Status__c, Unread_Count__c, ' +
            'Last_Message_Preview__c, Last_Inbound__c, Window_Expires__c, ' +
            'Contact__c, Contact__r.Name, Lead__c, Lead__r.Name, ' +
            'Channel__c, Channel__r.Name, OwnerId, Owner.Name, Owner_Agent__c, Owner_Agent__r.Name, ' +
            'Is_Group__c, Group_Name__c ' +
            'FROM Conversation__c WHERE ' + filter +
            ' ORDER BY Last_Inbound__c DESC NULLS LAST LIMIT 200';
        List<Conversation__c> rows = Database.query(soql);
        // The preview snippet is stored encrypted; decrypt for the inbox list.
        for (Conversation__c c : rows) {
            c.Last_Message_Preview__c = MaxDootCrypto.decrypt(c.Last_Message_Preview__c);
        }
        return rows;
    }

    /**
     * Resolve the WhatsApp conversation to show on a record page (Opportunity, Contact,
     * Lead, ...). Prefers a direct Contact/Lead link; otherwise matches the record's
     * phone number against an existing conversation. Returns null when none exists yet.
     */
    @AuraEnabled(cacheable=true)
    public static Id getConversationIdForRecord(Id recordId, String objectApiName, String phoneNumber) {
        if (objectApiName == 'Contact') {
            for (Conversation__c c : [
                SELECT Id FROM Conversation__c WHERE Contact__c = :recordId
                ORDER BY Last_Inbound__c DESC NULLS LAST LIMIT 1
            ]) {
                return c.Id;
            }
        } else if (objectApiName == 'Lead') {
            for (Conversation__c c : [
                SELECT Id FROM Conversation__c WHERE Lead__c = :recordId
                ORDER BY Last_Inbound__c DESC NULLS LAST LIMIT 1
            ]) {
                return c.Id;
            }
        }
        // Fall back to a phone-number suffix match (works for Opportunity or any object).
        String d = phoneNumber == null ? '' : phoneNumber.replaceAll('[^0-9]', '');
        if (d.length() >= 8) {
            String last = d.length() > 10 ? d.substring(d.length() - 10) : d;
            String likeExpr = '%' + last;
            for (Conversation__c c : [
                SELECT Id FROM Conversation__c WHERE Customer_Number__c LIKE :likeExpr
                ORDER BY Last_Inbound__c DESC NULLS LAST LIMIT 1
            ]) {
                return c.Id;
            }
        }
        return null;
    }

    @AuraEnabled(cacheable=true)
    public static List<Message__c> getMessages(Id conversationId) {
        List<Message__c> msgs = [
            SELECT Id, Direction__c, Body__c, Media_URL__c, Status__c, Timestamp__c, CreatedDate,
                   Sender_Name__c, Sender_Number__c
            FROM Message__c
            WHERE Conversation__c = :conversationId
            ORDER BY CreatedDate ASC
            LIMIT 1000
        ];
        // Bodies are stored encrypted at rest; decrypt in-memory for the authorized agent.
        for (Message__c m : msgs) {
            m.Body__c = MaxDootCrypto.decrypt(m.Body__c);
        }
        return msgs;
    }

    /**
     * Upload an attachment, link it to the conversation, and return a public URL.
     * heydoot delivers media as a link appended to the message, so we expose the file
     * through a ContentDistribution (public link) and send that URL as the mediaUrl.
     */
    @AuraEnabled
    public static String uploadAttachment(Id conversationId, String fileName, String base64Data) {
        if (String.isBlank(base64Data)) {
            throw new AuraHandledException('No file data received.');
        }
        String safeName = String.isBlank(fileName) ? 'attachment' : fileName;
        try {
            ContentVersion cv = new ContentVersion(
                Title = safeName,
                PathOnClient = safeName,
                VersionData = EncodingUtil.base64Decode(base64Data),
                FirstPublishLocationId = conversationId   // link the file to the conversation
            );
            insert cv;
            Id contentVersionId = [
                SELECT Id FROM ContentVersion WHERE Id = :cv.Id LIMIT 1
            ].Id;

            ContentDistribution cd = new ContentDistribution(
                Name = safeName,
                ContentVersionId = contentVersionId,
                PreferencesAllowViewInBrowser = true,
                PreferencesAllowOriginalDownload = true,
                PreferencesLinkLatestVersion = true,
                PreferencesNotifyOnVisit = false,
                PreferencesPasswordRequired = false,
                PreferencesExpires = false
            );
            insert cd;

            ContentDistribution saved = [
                SELECT ContentDownloadUrl, DistributionPublicUrl
                FROM ContentDistribution WHERE Id = :cd.Id LIMIT 1
            ];
            return String.isNotBlank(saved.ContentDownloadUrl)
                ? saved.ContentDownloadUrl : saved.DistributionPublicUrl;
        } catch (Exception e) {
            // Most common cause: "Content Deliveries and Public Links" not enabled in Setup.
            throw new AuraHandledException('Attachment upload failed: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static Message__c sendMessage(Id conversationId, String body, String mediaUrl) {
        if (String.isBlank(body) && String.isBlank(mediaUrl)) {
            throw new AuraHandledException('Message is empty.');
        }
        List<Conversation__c> convs = [
            SELECT Id, Customer_Number__c, Channel__c, Owner_Agent__c, Owner.Type,
                   Channel__r.Heydoot_Channel_Id__c, Channel__r.Bearer_Token__c, Channel__r.Active__c
            FROM Conversation__c WHERE Id = :conversationId LIMIT 1
        ];
        if (convs.isEmpty()) {
            throw new AuraHandledException('Conversation not found.');
        }
        Conversation__c conv = convs[0];
        if (conv.Channel__c == null || String.isBlank(conv.Channel__r.Bearer_Token__c)) {
            throw new AuraHandledException('This conversation has no connected channel (missing bearer token).');
        }

        MaxDootHeydootClient.SendResult result;
        try {
            result = MaxDootHeydootClient.sendMessage(
                conv.Channel__r.Bearer_Token__c, conv.Channel__r.Heydoot_Channel_Id__c,
                conv.Customer_Number__c, body, mediaUrl
            );
        } catch (Exception e) {
            throw new AuraHandledException('Send failed: ' + e.getMessage());
        }

        Message__c msg = new Message__c(
            Conversation__c = conversationId,
            Direction__c = 'Outbound',
            Body__c = MaxDootCrypto.encrypt(body),
            Media_URL__c = String.isBlank(mediaUrl) ? null : mediaUrl,
            Heydoot_Message_Id__c = result == null ? null : result.messageId,
            Status__c = (result != null && String.isNotBlank(result.status)) ? mapStatus(result.status) : 'Sent',
            Timestamp__c = System.now()
        );
        insert msg;

        Conversation__c convUpdate = new Conversation__c(
            Id = conversationId,
            Last_Message_Preview__c = MaxDootCrypto.encryptForField(
                String.isNotBlank(body) ? body : '[media]', 255)
        );
        // Claim-on-reply: the first agent to reply to an unassigned (queue-owned) thread
        // takes ownership, so the customer's replies route back to that agent.
        if (conv.Owner_Agent__c == null) {
            convUpdate.OwnerId = UserInfo.getUserId();
            convUpdate.Owner_Agent__c = UserInfo.getUserId();
        }
        update convUpdate;
        return msg;
    }

    /**
     * Start (or reuse) a conversation to a recipient and send the first outbound message.
     * Proactive outbound: the agent picks a channel + recipient instead of replying to an
     * existing inbound thread. Returns the conversation id so the UI can open the thread.
     *
     * The External_Key__c is computed the same way the inbound handler keys conversations
     * (channel discriminator + recipient number) so a later inbound reply lands on this
     * same conversation rather than spawning a duplicate.
     */
    @AuraEnabled
    public static Id startConversation(Id channelId, String toNumber, Id contactId,
                                       Id leadId, String body, String mediaUrl) {
        if (channelId == null) {
            throw new AuraHandledException('Select a channel to send from.');
        }
        if (String.isBlank(toNumber)) {
            throw new AuraHandledException('A recipient WhatsApp number is required.');
        }
        if (String.isBlank(body) && String.isBlank(mediaUrl)) {
            throw new AuraHandledException('Message is empty.');
        }

        List<Channel__c> chs = [
            SELECT Id, Heydoot_Channel_Id__c, Bearer_Token__c, WhatsApp_Number__c,
                   Scope__c, Assigned_Agent__c
            FROM Channel__c WHERE Id = :channelId LIMIT 1
        ];
        if (chs.isEmpty()) {
            throw new AuraHandledException('Channel not found.');
        }
        Channel__c ch = chs[0];
        if (String.isBlank(ch.Bearer_Token__c)) {
            throw new AuraHandledException('Selected channel has no bearer token configured.');
        }

        String channelKey = String.isNotBlank(ch.Heydoot_Channel_Id__c)
            ? ch.Heydoot_Channel_Id__c : digits(ch.WhatsApp_Number__c);
        // Canonicalize the number so an inbound reply (heydoot sends digits) threads onto
        // this same conversation instead of spawning a duplicate keyed with '+91…'.
        String externalKey = channelKey + ':' + MaxDootRouting.phoneKey(toNumber);

        List<Conversation__c> existing = [
            SELECT Id, Status__c FROM Conversation__c WHERE External_Key__c = :externalKey LIMIT 1
        ];

        // Build (but do not yet persist) the conversation so the heydoot callout
        // happens BEFORE any DML — Apex forbids a callout after uncommitted DML.
        Conversation__c conv;
        if (!existing.isEmpty()) {
            conv = existing[0];
            if (conv.Status__c == 'Closed') {
                conv.Status__c = 'Open';
            }
        } else {
            conv = new Conversation__c(
                External_Key__c = externalKey,
                Customer_Number__c = toNumber,
                Channel__c = ch.Id,
                Status__c = 'Open',
                Unread_Count__c = 0
            );
            if (contactId != null) {
                conv.Contact__c = contactId;
            }
            if (leadId != null) {
                conv.Lead__c = leadId;
            }
            if (contactId == null && leadId == null) {
                MaxDootRouting.Match m = MaxDootRouting.matchNumbers(new Set<String>{ toNumber }).get(toNumber);
                if (m != null) {
                    conv.Contact__c = m.contactId;
                    conv.Lead__c = m.leadId;
                }
            }
            // Proactive outbound: the initiating agent owns the thread (drives sharing).
            Id owner = MaxDootRouting.resolveOwner(ch);
            if (owner == null) {
                owner = UserInfo.getUserId();
            }
            conv.OwnerId = owner;
            conv.Owner_Agent__c = owner;
        }

        // 1. Callout first (no DML pending).
        MaxDootHeydootClient.SendResult result;
        try {
            result = MaxDootHeydootClient.sendMessage(
                ch.Bearer_Token__c, ch.Heydoot_Channel_Id__c, toNumber, body, mediaUrl
            );
        } catch (Exception e) {
            throw new AuraHandledException('Send failed: ' + e.getMessage());
        }

        // 2. Now persist the conversation + the outbound message.
        conv.Last_Message_Preview__c = MaxDootCrypto.encryptForField(
            String.isNotBlank(body) ? body : '[media]', 255);
        upsert conv;

        insert new Message__c(
            Conversation__c = conv.Id,
            Direction__c = 'Outbound',
            Body__c = MaxDootCrypto.encrypt(body),
            Media_URL__c = String.isBlank(mediaUrl) ? null : mediaUrl,
            Heydoot_Message_Id__c = result == null ? null : result.messageId,
            Status__c = (result != null && String.isNotBlank(result.status)) ? mapStatus(result.status) : 'Sent',
            Timestamp__c = System.now()
        );
        return conv.Id;
    }

    @AuraEnabled
    public static void markRead(Id conversationId) {
        update new Conversation__c(Id = conversationId, Unread_Count__c = 0);
    }

    /** Assign a conversation to the running user (claim it from the shared/unassigned pool). */
    @AuraEnabled
    public static void claimConversation(Id conversationId) {
        Id me = UserInfo.getUserId();
        update new Conversation__c(Id = conversationId, OwnerId = me, Owner_Agent__c = me);
    }

    /** Return a conversation to the unassigned queue pool. */
    @AuraEnabled
    public static void releaseConversation(Id conversationId) {
        Conversation__c cv = new Conversation__c(Id = conversationId, Owner_Agent__c = null);
        List<Group> qs = [SELECT Id FROM Group WHERE Type = 'Queue' AND DeveloperName = 'MaxDoot_Unassigned' LIMIT 1];
        if (!qs.isEmpty()) {
            cv.OwnerId = qs[0].Id;
        }
        update cv;
    }

    private static String digits(String s) {
        return s == null ? '' : s.replaceAll('[^0-9]', '');
    }

    private static String mapStatus(String raw) {
        String s = raw == null ? '' : raw.toLowerCase();
        if (s.contains('read')) return 'Read';
        if (s.contains('deliver')) return 'Delivered';
        if (s.contains('fail')) return 'Failed';
        if (s.contains('queue')) return 'Queued';
        return 'Sent';
    }
}
