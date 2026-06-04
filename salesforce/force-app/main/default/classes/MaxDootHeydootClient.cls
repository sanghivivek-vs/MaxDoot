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

    private static HttpRequest baseRequest(String method, String path, String bearerToken) {
        HttpRequest req = new HttpRequest();
        req.setMethod(method);
        req.setEndpoint(MaxDootConfig.namedCredential() + path);
        req.setHeader('Content-Type', 'application/json');
        // Multi-number: the per-channel bearer token identifies which WhatsApp number sends.
        // Falls back to the global config key only if a channel token is not provided.
        String token = String.isNotBlank(bearerToken) ? bearerToken : MaxDootConfig.get().Api_Key__c;
        if (String.isNotBlank(token)) {
            req.setHeader('Authorization', 'Bearer ' + token);
        }
        req.setTimeout(120000);
        return req;
    }

    private static String resolve(String template, String channelId) {
        return template == null ? '' : template.replace('{channelId}', channelId == null ? '' : channelId);
    }

    private static String digits(String s) {
        return s == null ? '' : s.replaceAll('[^0-9]', '');
    }

    /** Send a text and/or media message from a channel (identified by its bearer token). */
    public static SendResult sendMessage(String bearerToken, String channelId, String toNumber, String body, String mediaUrl) {
        MaxDoot_Config__mdt cfg = MaxDootConfig.get();
        HttpRequest req = baseRequest('POST', resolve(cfg.Send_Path__c, channelId), bearerToken);

        // heydoot external API is action-based: everything POSTs to the one endpoint.
        // Phone must be digits only (country code + number, no '+'). Media uploads use
        // a media-library fileId we don't have here, so a mediaUrl is sent as a link
        // appended to the message text.
        String message = String.isBlank(body) ? '' : body;
        if (String.isNotBlank(mediaUrl)) {
            message = String.isBlank(message) ? mediaUrl : message + '\n' + mediaUrl;
        }
        Map<String, Object> payload = new Map<String, Object>{
            'action' => 'send-message',
            'phone' => digits(toNumber),
            'message' => message
        };
        // The account can hold several WhatsApp sessions; when the channel pins a
        // heydoot session id, send from that specific number.
        if (String.isNotBlank(channelId)) {
            payload.put('sessionId', channelId);
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
    public static String getQr(String bearerToken, String channelId) {
        MaxDoot_Config__mdt cfg = MaxDootConfig.get();
        HttpRequest req = baseRequest('GET', resolve(cfg.QR_Path__c, channelId), bearerToken);
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
    public static String getStatus(String bearerToken, String channelId) {
        MaxDoot_Config__mdt cfg = MaxDootConfig.get();
        HttpRequest req = baseRequest('GET', resolve(cfg.Status_Path__c, channelId), bearerToken);
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
