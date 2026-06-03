/**
 * Test double for heydoot HTTP calls. Returns canned JSON based on the request path.
 */
@isTest
public class MaxDootCalloutMock implements HttpCalloutMock {
    public Integer statusCode = 200;

    public HttpResponse respond(HttpRequest req) {
        HttpResponse res = new HttpResponse();
        res.setHeader('Content-Type', 'application/json');
        res.setStatusCode(statusCode);
        String endpoint = req.getEndpoint();
        if (endpoint.contains('/messages')) {
            res.setBody('{"messageId":"hd-msg-123","status":"sent"}');
        } else if (endpoint.contains('/qr')) {
            res.setBody('{"qr":"data:image/png;base64,QQ=="}');
        } else if (endpoint.contains('/status')) {
            res.setBody('{"status":"connected"}');
        } else {
            res.setBody('{}');
        }
        return res;
    }
}
