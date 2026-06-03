/**
 * Thin client for the heydoot engine API. All calls route through the `heydoot`
 * Named Credential; paths are configurable via MaxDoot_Config__mdt so the contract
 * can be pinned to heydoot's real endpoints without code changes.
 */
public with sharing class MaxDootHeydootClient {

    public class HeydootException extends Exception {}

    /** Result of an outbound send. */
    public class SendResult {
        @AuraEnabled public String messageId;
        @AuraEnabled public String status;
    }

    private static HttpRequest baseRequest(String method, String path) {
        MaxDoot_Config__mdt cfg = MaxDootConfig.get();
        HttpRequest req = new HttpRequest();
        req.setMethod(method);
        req.setEndpoint(MaxDootConfig.namedCredential() + path);
        req.setHeader('Content-Type', 'application/json');
        if (String.isNotBlank(cfg.Api_Key__c)) {
            req.setHeader('Authorization', 'Bearer ' + cfg.Api_Key__c);
        }
        req.setTimeout(120000);
        return req;
    }

    private static String resolve(String template, String channelId) {
        return template == null ? '' : template.replace('{channelId}', channelId == null ? '' : channelId);
    }

    /** Send a text and/or media message through a channel. Returns the heydoot message id. */
    public static SendResult sendMessage(String channelId, String toNumber, String body, String mediaUrl) {
        MaxDoot_Config__mdt cfg = MaxDootConfig.get();
        HttpRequest req = baseRequest('POST', resolve(cfg.Send_Path__c, channelId));

        Map<String, Object> payload = new Map<String, Object>{
            'to' => toNumber,
            'type' => String.isBlank(mediaUrl) ? 'text' : 'media'
        };
        if (String.isNotBlank(body)) {
            payload.put('text', body);
        }
        if (String.isNotBlank(mediaUrl)) {
            payload.put('mediaUrl', mediaUrl);
        }
        req.setBody(JSON.serialize(payload));

        HttpResponse res = new Http().send(req);
        if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
            throw new HeydootException('heydoot send failed (' + res.getStatusCode() + '): ' + res.getBody());
        }

        SendResult result = new SendResult();
        try {
            Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            // Accept a few likely key names so we are resilient to heydoot's exact shape.
            Object id = parsed.containsKey('messageId') ? parsed.get('messageId')
                      : parsed.containsKey('id') ? parsed.get('id')
                      : parsed.get('message_id');
            result.messageId = id == null ? null : String.valueOf(id);
            result.status = parsed.containsKey('status') ? String.valueOf(parsed.get('status')) : 'Sent';
        } catch (Exception e) {
            result.status = 'Sent';
        }
        return result;
    }

    /** Fetch the login QR for a channel. Returns the raw body (data-URL or QR string). */
    public static String getQr(String channelId) {
        MaxDoot_Config__mdt cfg = MaxDootConfig.get();
        HttpRequest req = baseRequest('GET', resolve(cfg.QR_Path__c, channelId));
        HttpResponse res = new Http().send(req);
        if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
            throw new HeydootException('heydoot QR fetch failed (' + res.getStatusCode() + '): ' + res.getBody());
        }
        String bodyText = res.getBody();
        // If JSON, try to extract a "qr" field; otherwise return as-is.
        try {
            Object parsed = JSON.deserializeUntyped(bodyText);
            if (parsed instanceof Map<String, Object>) {
                Map<String, Object> m = (Map<String, Object>) parsed;
                if (m.containsKey('qr')) return String.valueOf(m.get('qr'));
                if (m.containsKey('qrCode')) return String.valueOf(m.get('qrCode'));
            }
        } catch (Exception ignored) {
            // not JSON; fall through
        }
        return bodyText;
    }

    /** Fetch the session status for a channel: Connected | Disconnected | NeedsScan. */
    public static String getStatus(String channelId) {
        MaxDoot_Config__mdt cfg = MaxDootConfig.get();
        HttpRequest req = baseRequest('GET', resolve(cfg.Status_Path__c, channelId));
        HttpResponse res = new Http().send(req);
        if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
            throw new HeydootException('heydoot status fetch failed (' + res.getStatusCode() + '): ' + res.getBody());
        }
        try {
            Map<String, Object> m = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            Object s = m.containsKey('status') ? m.get('status') : m.get('state');
            return normalizeStatus(s == null ? null : String.valueOf(s));
        } catch (Exception e) {
            return normalizeStatus(res.getBody());
        }
    }

    @TestVisible
    private static String normalizeStatus(String raw) {
        if (String.isBlank(raw)) return 'NeedsScan';
        String s = raw.toLowerCase();
        if (s.contains('connect') || s.contains('ready') || s.contains('online')) return 'Connected';
        if (s.contains('scan') || s.contains('qr') || s.contains('pair')) return 'NeedsScan';
        return 'Disconnected';
    }
}
