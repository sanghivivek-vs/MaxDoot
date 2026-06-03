/**
 * Apex controller backing the MaxDoot inbox and conversation LWCs:
 * lists conversations, loads a thread, sends outbound messages via heydoot, and
 * clears unread counts.
 */
public with sharing class MaxDootSendController {

    @AuraEnabled(cacheable=true)
    public static List<Conversation__c> getOpenConversations(String statusFilter) {
        String status = String.isBlank(statusFilter) ? 'Open' : statusFilter;
        return [
            SELECT Id, Name, Customer_Number__c, Status__c, Unread_Count__c,
                   Last_Message_Preview__c, Last_Inbound__c, Window_Expires__c,
                   Contact__c, Contact__r.Name, Lead__c, Lead__r.Name,
                   Channel__c, Channel__r.Name, Owner_Agent__c, Owner_Agent__r.Name
            FROM Conversation__c
            WHERE Status__c = :status
            ORDER BY Last_Inbound__c DESC NULLS LAST
            LIMIT 200
        ];
    }

    @AuraEnabled(cacheable=true)
    public static List<Message__c> getMessages(Id conversationId) {
        return [
            SELECT Id, Direction__c, Body__c, Media_URL__c, Status__c, Timestamp__c, CreatedDate
            FROM Message__c
            WHERE Conversation__c = :conversationId
            ORDER BY CreatedDate ASC
            LIMIT 1000
        ];
    }

    @AuraEnabled
    public static Message__c sendMessage(Id conversationId, String body, String mediaUrl) {
        if (String.isBlank(body) && String.isBlank(mediaUrl)) {
            throw new AuraHandledException('Message is empty.');
        }
        List<Conversation__c> convs = [
            SELECT Id, Customer_Number__c, Channel__r.Heydoot_Channel_Id__c, Channel__r.Active__c
            FROM Conversation__c WHERE Id = :conversationId LIMIT 1
        ];
        if (convs.isEmpty()) {
            throw new AuraHandledException('Conversation not found.');
        }
        Conversation__c conv = convs[0];
        if (conv.Channel__c == null || String.isBlank(conv.Channel__r.Heydoot_Channel_Id__c)) {
            throw new AuraHandledException('This conversation has no connected channel.');
        }

        MaxDootHeydootClient.SendResult result;
        try {
            result = MaxDootHeydootClient.sendMessage(
                conv.Channel__r.Heydoot_Channel_Id__c, conv.Customer_Number__c, body, mediaUrl
            );
        } catch (Exception e) {
            throw new AuraHandledException('Send failed: ' + e.getMessage());
        }

        Message__c msg = new Message__c(
            Conversation__c = conversationId,
            Direction__c = 'Outbound',
            Body__c = body,
            Media_URL__c = String.isBlank(mediaUrl) ? null : mediaUrl,
            Heydoot_Message_Id__c = result == null ? null : result.messageId,
            Status__c = (result != null && String.isNotBlank(result.status)) ? mapStatus(result.status) : 'Sent',
            Timestamp__c = System.now()
        );
        insert msg;

        update new Conversation__c(
            Id = conversationId,
            Last_Message_Preview__c = String.isNotBlank(body)
                ? (body.length() > 255 ? body.substring(0, 255) : body) : '[media]'
        );
        return msg;
    }

    @AuraEnabled
    public static void markRead(Id conversationId) {
        update new Conversation__c(Id = conversationId, Unread_Count__c = 0);
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
