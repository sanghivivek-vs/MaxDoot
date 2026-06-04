/**
 * Unit tests for the MaxDoot Apex layer: inbound webhook + event handling,
 * outbound send, channel/QR controller and routing.
 */
@isTest
private class MaxDootTest {

    private static MaxDoot_Config__mdt cfg() {
        return new MaxDoot_Config__mdt(
            Inbound_Token__c = 'secret',
            Api_Key__c = 'apikey',
            Send_Path__c = '/v1/channels/{channelId}/messages',
            QR_Path__c = '/v1/channels/{channelId}/qr',
            Status_Path__c = '/v1/channels/{channelId}/status'
        );
    }

    private static Channel__c makeChannel() {
        Channel__c ch = new Channel__c(
            Name = 'Sales',
            Heydoot_Channel_Id__c = 'chan-1',
            WhatsApp_Number__c = '+10000000000',
            Bearer_Token__c = 'tok-secret',
            Scope__c = 'Org',
            Session_Status__c = 'Connected',
            Active__c = true
        );
        insert ch;
        return ch;
    }

    @isTest
    static void inboundWebhook_createsConversationAndMessage() {
        MaxDootConfig.testOverride = cfg();
        makeChannel();

        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/maxdoot/inbound';
        req.httpMethod = 'POST';
        req.headers.put('X-MaxDoot-Token', 'secret');
        req.requestBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{
            'type' => 'message',
            'channelId' => 'chan-1',
            'from' => '+19998887777',
            'to' => '+10000000000',
            'messageId' => 'hd-1',
            'body' => 'Hello there',
            'timestamp' => '2026-06-03T10:00:00Z'
        }));
        RestContext.request = req;
        RestContext.response = new RestResponse();

        Test.startTest();
        MaxDootInboundResource.doPost();
        Test.stopTest(); // delivers the platform event -> trigger -> handler

        System.assertEquals(200, RestContext.response.statusCode, 'should accept');
        List<Conversation__c> convs = [SELECT Id, Customer_Number__c, Unread_Count__c FROM Conversation__c];
        System.assertEquals(1, convs.size(), 'one conversation created');
        System.assertEquals(1, [SELECT COUNT() FROM Message__c WHERE Direction__c = 'Inbound']);
    }

    @isTest
    static void inboundWebhook_threadsOntoExistingConversation() {
        // Regression: an inbound reply must land on the already-open conversation
        // (e.g. a thread started by a proactive outbound send), not throw or duplicate.
        MaxDootConfig.testOverride = cfg();
        makeChannel();
        Conversation__c existing = new Conversation__c(
            External_Key__c = 'chan-1:+19998887777',
            Customer_Number__c = '+19998887777',
            Status__c = 'Closed', // also verifies reopen
            Unread_Count__c = 0
        );
        insert existing;

        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/maxdoot/inbound';
        req.httpMethod = 'POST';
        req.headers.put('X-MaxDoot-Token', 'secret');
        req.requestBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{
            'type' => 'message',
            'channelId' => 'chan-1',
            'from' => '+19998887777',
            'to' => '+10000000000',
            'messageId' => 'hd-reply-1',
            'body' => 'Customer reply',
            'timestamp' => '2026-06-03T11:00:00Z'
        }));
        RestContext.request = req;
        RestContext.response = new RestResponse();

        Test.startTest();
        MaxDootInboundResource.doPost();
        Test.stopTest();

        System.assertEquals(1, [SELECT COUNT() FROM Conversation__c], 'no duplicate conversation');
        Conversation__c after = [SELECT Status__c, Unread_Count__c FROM Conversation__c WHERE Id = :existing.Id];
        System.assertEquals('Open', after.Status__c, 'closed conversation reopens on inbound');
        System.assertEquals(1, after.Unread_Count__c, 'unread incremented');
        System.assertEquals(1, [SELECT COUNT() FROM Message__c WHERE Conversation__c = :existing.Id AND Direction__c = 'Inbound']);
    }

    @isTest
    static void inboundWebhook_rejectsBadToken() {
        MaxDootConfig.testOverride = cfg();
        RestRequest req = new RestRequest();
        req.httpMethod = 'POST';
        req.headers.put('X-MaxDoot-Token', 'wrong');
        req.requestBody = Blob.valueOf('{"type":"message"}');
        RestContext.request = req;
        RestContext.response = new RestResponse();

        MaxDootInboundResource.doPost();
        System.assertEquals(401, RestContext.response.statusCode);
    }

    @isTest
    static void inboundHandler_isIdempotent() {
        MaxDootConfig.testOverride = cfg();
        makeChannel();
        MaxDoot_Inbound__e e = new MaxDoot_Inbound__e(
            Event_Type__c = 'message', Channel_Id__c = 'chan-1',
            From_Number__c = '+15551112222', Message_Id__c = 'dup-1', Body__c = 'hi'
        );
        MaxDootInboundHandler.handle(new List<MaxDoot_Inbound__e>{ e });
        // Replay the same message id.
        MaxDootInboundHandler.handle(new List<MaxDoot_Inbound__e>{ e });
        System.assertEquals(1, [SELECT COUNT() FROM Message__c WHERE Heydoot_Message_Id__c = 'dup-1']);
    }

    @isTest
    static void inboundHandler_matchesChannelByNumber() {
        MaxDootConfig.testOverride = cfg();
        makeChannel(); // WhatsApp_Number__c = +10000000000
        MaxDoot_Inbound__e e = new MaxDoot_Inbound__e(
            Event_Type__c = 'message', Channel_Id__c = null,
            To_Number__c = '+1 000-000-0000', From_Number__c = '+15551239999',
            Message_Id__c = 'bynum-1', Body__c = 'hi by number'
        );
        MaxDootInboundHandler.handle(new List<MaxDoot_Inbound__e>{ e });
        Conversation__c cv = [
            SELECT Channel__c FROM Conversation__c WHERE Customer_Number__c = '+15551239999' LIMIT 1
        ];
        System.assertNotEquals(null, cv.Channel__c, 'channel matched by destination number');
    }

    @isTest
    static void statusEvent_updatesMessage() {
        MaxDootConfig.testOverride = cfg();
        Channel__c ch = makeChannel();
        Conversation__c conv = new Conversation__c(
            External_Key__c = 'chan-1:+1444', Customer_Number__c = '+1444',
            Channel__c = ch.Id, Status__c = 'Open'
        );
        insert conv;
        insert new Message__c(
            Conversation__c = conv.Id, Direction__c = 'Outbound',
            Body__c = 'sent', Heydoot_Message_Id__c = 'out-1', Status__c = 'Sent'
        );
        MaxDootInboundHandler.handle(new List<MaxDoot_Inbound__e>{
            new MaxDoot_Inbound__e(Event_Type__c = 'status', Message_Id__c = 'out-1', Msg_Status__c = 'read')
        });
        System.assertEquals('Read', [SELECT Status__c FROM Message__c WHERE Heydoot_Message_Id__c = 'out-1'].Status__c);
    }

    @isTest
    static void sendMessage_callsHeydootAndStoresMessage() {
        MaxDootConfig.testOverride = cfg();
        Channel__c ch = makeChannel();
        Conversation__c conv = new Conversation__c(
            External_Key__c = 'chan-1:+1777', Customer_Number__c = '+1777',
            Channel__c = ch.Id, Status__c = 'Open'
        );
        insert conv;

        Test.setMock(HttpCalloutMock.class, new MaxDootCalloutMock());
        Test.startTest();
        Message__c m = MaxDootSendController.sendMessage(conv.Id, 'Hi back', null);
        Test.stopTest();

        System.assertEquals('Outbound', m.Direction__c);
        System.assertEquals('hd-msg-123', m.Heydoot_Message_Id__c);
    }

    @isTest
    static void sendMessage_emptyThrows() {
        MaxDootConfig.testOverride = cfg();
        Channel__c ch = makeChannel();
        Conversation__c conv = new Conversation__c(
            External_Key__c = 'chan-1:+1888', Customer_Number__c = '+1888',
            Channel__c = ch.Id, Status__c = 'Open'
        );
        insert conv;
        try {
            MaxDootSendController.sendMessage(conv.Id, '', '');
            System.assert(false, 'should have thrown');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    @isTest
    static void startConversation_createsConversationAndSends() {
        MaxDootConfig.testOverride = cfg();
        Channel__c ch = makeChannel();

        Test.setMock(HttpCalloutMock.class, new MaxDootCalloutMock());
        Test.startTest();
        Id convId = MaxDootSendController.startConversation(
            ch.Id, '+15551234567', null, null, 'Hello from MaxDoot', null
        );
        Test.stopTest();

        System.assertNotEquals(null, convId, 'returns the conversation id');
        Conversation__c conv = [
            SELECT External_Key__c, Customer_Number__c, Channel__c, Status__c, Owner_Agent__c
            FROM Conversation__c WHERE Id = :convId
        ];
        System.assertEquals('chan-1:+15551234567', conv.External_Key__c, 'keyed like inbound');
        System.assertEquals(ch.Id, conv.Channel__c);
        System.assertEquals(UserInfo.getUserId(), conv.Owner_Agent__c, 'Org scope falls back to current user');
        System.assertEquals(1, [
            SELECT COUNT() FROM Message__c WHERE Conversation__c = :convId AND Direction__c = 'Outbound'
        ]);
    }

    @isTest
    static void startConversation_reusesExistingConversation() {
        MaxDootConfig.testOverride = cfg();
        Channel__c ch = makeChannel();
        Conversation__c existing = new Conversation__c(
            External_Key__c = 'chan-1:+15559999999', Customer_Number__c = '+15559999999',
            Channel__c = ch.Id, Status__c = 'Closed'
        );
        insert existing;

        Test.setMock(HttpCalloutMock.class, new MaxDootCalloutMock());
        Test.startTest();
        Id convId = MaxDootSendController.startConversation(
            ch.Id, '+15559999999', null, null, 'Reopen please', null
        );
        Test.stopTest();

        System.assertEquals(existing.Id, convId, 'reuses the existing conversation');
        System.assertEquals(1, [SELECT COUNT() FROM Conversation__c], 'no duplicate created');
        System.assertEquals('Open', [SELECT Status__c FROM Conversation__c WHERE Id = :convId].Status__c);
    }

    @isTest
    static void startConversation_validates() {
        MaxDootConfig.testOverride = cfg();
        Channel__c ch = makeChannel();
        try {
            MaxDootSendController.startConversation(ch.Id, '', null, null, 'hi', null);
            System.assert(false, 'should require a recipient number');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    @isTest
    static void queries_work() {
        MaxDootConfig.testOverride = cfg();
        Channel__c ch = makeChannel();
        Conversation__c conv = new Conversation__c(
            External_Key__c = 'chan-1:+1999', Customer_Number__c = '+1999',
            Channel__c = ch.Id, Status__c = 'Open', Unread_Count__c = 3
        );
        insert conv;
        insert new Message__c(Conversation__c = conv.Id, Direction__c = 'Inbound', Body__c = 'yo');

        System.assertEquals(1, MaxDootSendController.getOpenConversations('Open').size());
        System.assertEquals(1, MaxDootSendController.getMessages(conv.Id).size());
        MaxDootSendController.markRead(conv.Id);
        System.assertEquals(0, [SELECT Unread_Count__c FROM Conversation__c WHERE Id = :conv.Id].Unread_Count__c);
    }

    @isTest
    static void channelController_qrAndStatus() {
        MaxDootConfig.testOverride = cfg();
        Channel__c ch = makeChannel();
        Test.setMock(HttpCalloutMock.class, new MaxDootCalloutMock());
        Test.startTest();
        String qr = MaxDootChannelController.getQr(ch.Id);
        String status = MaxDootChannelController.refreshStatus(ch.Id);
        Test.stopTest();
        System.assert(qr.startsWith('data:image'), 'QR returned');
        System.assertEquals('Connected', status);
        System.assertEquals(1, MaxDootChannelController.getChannels().size());
    }

    @isTest
    static void dashboard_stats() {
        MaxDootConfig.testOverride = cfg();
        Channel__c ch = makeChannel();
        Conversation__c conv = new Conversation__c(
            External_Key__c = 'chan-1:+1212', Customer_Number__c = '+1212',
            Channel__c = ch.Id, Status__c = 'Open', Unread_Count__c = 2
        );
        insert conv;
        insert new Message__c(Conversation__c = conv.Id, Direction__c = 'Inbound', Body__c = 'hey');

        MaxDootDashboardController.Stats s = MaxDootDashboardController.getStats();
        System.assertEquals(1, s.openConversations);
        System.assertEquals(1, s.unassigned);
        System.assertEquals(2, s.unread);
        System.assertEquals(1, s.connectedChannels);
        System.assert(s.messagesToday >= 1);
    }

    @isTest
    static void branding_returnsConfiguredValuesAndHidesPlaceholders() {
        MaxDoot_Config__mdt c = cfg();
        c.Company_Name__c = 'Max Health';
        c.Tagline__c = 'Care that connects';
        c.Support_Email__c = 'help@example.com';
        c.Support_Phone__c = 'REPLACE_WITH_MAX_HEALTH_SUPPORT_PHONE';
        MaxDootConfig.testOverride = c;

        MaxDootBrandingController.Branding b = MaxDootBrandingController.getBranding();
        System.assertEquals('Max Health', b.companyName);
        System.assertEquals('help@example.com', b.supportEmail);
        System.assertEquals(null, b.supportPhone, 'placeholder should be hidden');
    }

    @isTest
    static void routing_matchesContactByPhone() {
        Contact c = new Contact(LastName = 'Doe', Phone = '+1 (415) 555-2671');
        insert c;
        Map<String, MaxDootRouting.Match> m = MaxDootRouting.matchNumbers(new Set<String>{ '14155552671' });
        System.assertEquals(c.Id, m.get('14155552671').contactId);
    }
}
