/**
 * Webhook endpoint heydoot POSTs to on every inbound message and status update.
 *   POST /services/apexrest/maxdoot/inbound
 *   Header: X-MaxDoot-Token: <shared secret from MaxDoot_Config__mdt.Inbound_Token__c>
 *
 * Accepts a single event object or a batch under "events". Each event is validated,
 * mapped to a MaxDoot_Inbound__e and published; persistence happens in the PE trigger.
 */
@RestResource(urlMapping='/maxdoot/inbound/*')
global without sharing class MaxDootInboundResource {

    @HttpPost
    global static void doPost() {
        RestResponse res = RestContext.response;
        if (res == null) {
            res = new RestResponse();
            RestContext.response = res;
        }

        // --- auth ---
        String provided = RestContext.request.headers.get('X-MaxDoot-Token');
        String expected = MaxDootConfig.get().Inbound_Token__c;
        if (String.isBlank(expected) || provided != expected) {
            res.statusCode = 401;
            res.responseBody = Blob.valueOf('{"error":"unauthorized"}');
            return;
        }

        try {
            String body = RestContext.request.requestBody == null
                ? '' : RestContext.request.requestBody.toString();
            Object parsed = JSON.deserializeUntyped(body);

            List<Object> rawEvents = new List<Object>();
            if (parsed instanceof List<Object>) {
                rawEvents = (List<Object>) parsed;
            } else if (parsed instanceof Map<String, Object>) {
                Map<String, Object> m = (Map<String, Object>) parsed;
                if (m.containsKey('events') && m.get('events') instanceof List<Object>) {
                    rawEvents = (List<Object>) m.get('events');
                } else {
                    rawEvents.add(m);
                }
            }

            List<MaxDoot_Inbound__e> toPublish = new List<MaxDoot_Inbound__e>();
            for (Object o : rawEvents) {
                if (!(o instanceof Map<String, Object>)) continue;
                toPublish.add(toEvent((Map<String, Object>) o));
            }

            if (!toPublish.isEmpty()) {
                List<Database.SaveResult> srs = EventBus.publish(toPublish);
                for (Database.SaveResult sr : srs) {
                    if (!sr.isSuccess()) {
                        res.statusCode = 500;
                        res.responseBody = Blob.valueOf('{"error":"publish_failed"}');
                        return;
                    }
                }
            }
            res.statusCode = 200;
            res.responseBody = Blob.valueOf('{"accepted":' + toPublish.size() + '}');
        } catch (Exception e) {
            res.statusCode = 400;
            res.responseBody = Blob.valueOf('{"error":"bad_request","detail":"' + e.getMessage().escapeJava() + '"}');
        }
    }

    @TestVisible
    private static MaxDoot_Inbound__e toEvent(Map<String, Object> m) {
        String type = str(m, 'type');
        if (String.isBlank(type)) type = 'message';
        return new MaxDoot_Inbound__e(
            Event_Type__c = type,
            Channel_Id__c = str(m, 'channelId'),
            From_Number__c = firstNonBlank(str(m, 'from'), str(m, 'fromNumber')),
            To_Number__c = firstNonBlank(str(m, 'to'), str(m, 'toNumber')),
            Direction__c = firstNonBlank(str(m, 'direction'), 'Inbound'),
            Message_Id__c = firstNonBlank(str(m, 'messageId'), str(m, 'id')),
            Body__c = firstNonBlank(str(m, 'body'), str(m, 'text')),
            Media_URL__c = firstNonBlank(str(m, 'mediaUrl'), str(m, 'media_url')),
            Msg_Status__c = str(m, 'status'),
            Timestamp_Iso__c = firstNonBlank(str(m, 'timestamp'), str(m, 'ts'))
        );
    }

    private static String str(Map<String, Object> m, String key) {
        Object v = m.get(key);
        return v == null ? null : String.valueOf(v);
    }

    private static String firstNonBlank(String a, String b) {
        return String.isNotBlank(a) ? a : b;
    }
}
