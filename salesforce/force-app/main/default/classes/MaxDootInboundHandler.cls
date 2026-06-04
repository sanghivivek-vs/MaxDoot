/**
 * Processes MaxDoot_Inbound__e platform events into Conversation__c / Message__c records.
 * Bulk-safe and idempotent (keyed on Heydoot_Message_Id__c) because platform events
 * are delivered at-least-once.
 */
public without sharing class MaxDootInboundHandler {

    public static void handle(List<MaxDoot_Inbound__e> events) {
        List<MaxDoot_Inbound__e> messageEvents = new List<MaxDoot_Inbound__e>();
        List<MaxDoot_Inbound__e> statusEvents = new List<MaxDoot_Inbound__e>();
        for (MaxDoot_Inbound__e e : events) {
            if (e.Event_Type__c == 'status') {
                statusEvents.add(e);
            } else {
                messageEvents.add(e);
            }
        }
        if (!statusEvents.isEmpty()) {
            applyStatusUpdates(statusEvents);
        }
        if (!messageEvents.isEmpty()) {
            applyInboundMessages(messageEvents);
        }
    }

    // ---- Delivery / read receipts ------------------------------------------------

    private static void applyStatusUpdates(List<MaxDoot_Inbound__e> events) {
        Map<String, String> statusByMsgId = new Map<String, String>();
        for (MaxDoot_Inbound__e e : events) {
            if (String.isNotBlank(e.Message_Id__c) && String.isNotBlank(e.Msg_Status__c)) {
                statusByMsgId.put(e.Message_Id__c, normalizeMsgStatus(e.Msg_Status__c));
            }
        }
        if (statusByMsgId.isEmpty()) return;

        List<Message__c> toUpdate = new List<Message__c>();
        for (Message__c m : [
            SELECT Id, Heydoot_Message_Id__c, Status__c
            FROM Message__c
            WHERE Heydoot_Message_Id__c IN :statusByMsgId.keySet()
        ]) {
            m.Status__c = statusByMsgId.get(m.Heydoot_Message_Id__c);
            toUpdate.add(m);
        }
        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
    }

    // ---- Inbound messages --------------------------------------------------------

    private static void applyInboundMessages(List<MaxDoot_Inbound__e> events) {
        // 1. Idempotency: drop events whose message id we already stored.
        Set<String> incomingIds = new Set<String>();
        for (MaxDoot_Inbound__e e : events) {
            if (String.isNotBlank(e.Message_Id__c)) incomingIds.add(e.Message_Id__c);
        }
        Set<String> existingIds = new Set<String>();
        for (Message__c m : [SELECT Heydoot_Message_Id__c FROM Message__c WHERE Heydoot_Message_Id__c IN :incomingIds]) {
            existingIds.add(m.Heydoot_Message_Id__c);
        }

        // 2. Load all channels so we can match by heydoot channel id OR by our WhatsApp number
        //    (the bearer-token model means inbound may not carry a path channel id).
        Map<String, Channel__c> channelByHeydootId = new Map<String, Channel__c>();
        Map<String, Channel__c> channelByNumber = new Map<String, Channel__c>();
        for (Channel__c c : [
            SELECT Id, Heydoot_Channel_Id__c, WhatsApp_Number__c, Scope__c, Assigned_Agent__c
            FROM Channel__c LIMIT 1000
        ]) {
            if (String.isNotBlank(c.Heydoot_Channel_Id__c)) {
                channelByHeydootId.put(c.Heydoot_Channel_Id__c, c);
            }
            if (String.isNotBlank(c.WhatsApp_Number__c)) {
                channelByNumber.put(digits(c.WhatsApp_Number__c), c);
            }
        }

        List<MaxDoot_Inbound__e> fresh = new List<MaxDoot_Inbound__e>();
        Set<String> numbers = new Set<String>();
        Set<String> convKeys = new Set<String>();
        Map<MaxDoot_Inbound__e, Channel__c> channelForEvent = new Map<MaxDoot_Inbound__e, Channel__c>();
        for (MaxDoot_Inbound__e e : events) {
            if (String.isNotBlank(e.Message_Id__c) && existingIds.contains(e.Message_Id__c)) continue;
            fresh.add(e);
            numbers.add(e.From_Number__c);
            Channel__c ch = resolveChannel(e, channelByHeydootId, channelByNumber);
            channelForEvent.put(e, ch);
            convKeys.add(convKey(channelKeyOf(e), e.From_Number__c));
        }
        if (fresh.isEmpty()) return;

        Map<String, Conversation__c> convByKey = new Map<String, Conversation__c>();
        for (Conversation__c cv : [
            SELECT Id, External_Key__c, Unread_Count__c, Status__c
            FROM Conversation__c WHERE External_Key__c IN :convKeys
        ]) {
            convByKey.put(cv.External_Key__c, cv);
        }

        // 3. Match numbers for brand-new conversations.
        Map<String, MaxDootRouting.Match> matches = MaxDootRouting.matchNumbers(numbers);

        // 4. Build/refresh conversations.
        Map<String, MaxDoot_Inbound__e> latestByKey = new Map<String, MaxDoot_Inbound__e>();
        for (MaxDoot_Inbound__e e : fresh) {
            latestByKey.put(convKey(channelKeyOf(e), e.From_Number__c), e);
        }

        List<Conversation__c> toUpsert = new List<Conversation__c>();
        for (String key : latestByKey.keySet()) {
            MaxDoot_Inbound__e e = latestByKey.get(key);
            Channel__c ch = channelForEvent.get(e);
            Conversation__c cv = convByKey.get(key);
            if (cv == null) {
                cv = new Conversation__c(
                    External_Key__c = key,
                    Customer_Number__c = e.From_Number__c,
                    Status__c = 'Open',
                    Unread_Count__c = 0
                );
                if (ch != null) {
                    cv.Channel__c = ch.Id;
                    cv.Owner_Agent__c = MaxDootRouting.resolveOwner(ch);
                }
                MaxDootRouting.Match mt = matches.get(e.From_Number__c);
                if (mt != null) {
                    cv.Contact__c = mt.contactId;
                    cv.Lead__c = mt.leadId;
                }
            }
            cv.Last_Inbound__c = System.now();
            cv.Window_Expires__c = System.now().addHours(24);
            cv.Last_Message_Preview__c = preview(e.Body__c, e.Media_URL__c);
            cv.Unread_Count__c = (cv.Unread_Count__c == null ? 0 : cv.Unread_Count__c)
                                 + countFor(fresh, key);
            if (cv.Status__c == 'Closed') cv.Status__c = 'Open';
            toUpsert.add(cv);
        }
        upsert toUpsert External_Key__c;

        // 5. Re-read ids by key (upsert by external id does not always backfill Id on new rows reliably).
        Map<String, Id> convIdByKey = new Map<String, Id>();
        for (Conversation__c cv : [SELECT Id, External_Key__c FROM Conversation__c WHERE External_Key__c IN :convKeys]) {
            convIdByKey.put(cv.External_Key__c, cv.Id);
        }

        // 6. Create messages.
        List<Message__c> toInsert = new List<Message__c>();
        for (MaxDoot_Inbound__e e : fresh) {
            Id convId = convIdByKey.get(convKey(channelKeyOf(e), e.From_Number__c));
            if (convId == null) continue;
            toInsert.add(new Message__c(
                Conversation__c = convId,
                Direction__c = 'Inbound',
                Body__c = e.Body__c,
                Media_URL__c = String.isBlank(e.Media_URL__c) ? null : e.Media_URL__c,
                Heydoot_Message_Id__c = e.Message_Id__c,
                Status__c = 'Delivered',
                Timestamp__c = parseTs(e.Timestamp_Iso__c)
            ));
        }
        if (!toInsert.isEmpty()) {
            insert toInsert;
        }
    }

    // ---- helpers ----------------------------------------------------------------

    private static Integer countFor(List<MaxDoot_Inbound__e> events, String key) {
        Integer n = 0;
        for (MaxDoot_Inbound__e e : events) {
            if (convKey(channelKeyOf(e), e.From_Number__c) == key) n++;
        }
        return n;
    }

    @TestVisible
    private static String convKey(String channelId, String phone) {
        return (channelId == null ? '' : channelId) + ':' + (phone == null ? '' : phone);
    }

    /** Stable per-event channel discriminator: heydoot channel id if present, else our number. */
    @TestVisible
    private static String channelKeyOf(MaxDoot_Inbound__e e) {
        if (String.isNotBlank(e.Channel_Id__c)) return e.Channel_Id__c;
        return String.isBlank(e.To_Number__c) ? 'unknown' : digits(e.To_Number__c);
    }

    private static Channel__c resolveChannel(MaxDoot_Inbound__e e,
            Map<String, Channel__c> byHeydootId, Map<String, Channel__c> byNumber) {
        if (String.isNotBlank(e.Channel_Id__c) && byHeydootId.containsKey(e.Channel_Id__c)) {
            return byHeydootId.get(e.Channel_Id__c);
        }
        if (String.isNotBlank(e.To_Number__c)) {
            return byNumber.get(digits(e.To_Number__c));
        }
        return null;
    }

    private static String digits(String s) {
        return s == null ? '' : s.replaceAll('[^0-9]', '');
    }

    private static String preview(String body, String mediaUrl) {
        if (String.isNotBlank(body)) {
            return body.length() > 255 ? body.substring(0, 255) : body;
        }
        return String.isNotBlank(mediaUrl) ? '[media]' : '';
    }

    private static Datetime parseTs(String iso) {
        if (String.isBlank(iso)) return System.now();
        try {
            return (Datetime) JSON.deserialize('"' + iso + '"', Datetime.class);
        } catch (Exception e) {
            return System.now();
        }
    }

    @TestVisible
    private static String normalizeMsgStatus(String raw) {
        if (String.isBlank(raw)) return 'Sent';
        String s = raw.toLowerCase();
        if (s.contains('read')) return 'Read';
        if (s.contains('deliver')) return 'Delivered';
        if (s.contains('fail') || s.contains('error')) return 'Failed';
        if (s.contains('sent')) return 'Sent';
        return 'Sent';
    }
}
