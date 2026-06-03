/**
 * Controller for the channel-setup LWC: lists channels, fetches the heydoot login
 * QR for in-Salesforce scanning, and refreshes/persists session status.
 */
public with sharing class MaxDootChannelController {

    @AuraEnabled(cacheable=true)
    public static List<Channel__c> getChannels() {
        return [
            SELECT Id, Name, Heydoot_Channel_Id__c, WhatsApp_Number__c, Scope__c,
                   Team__c, Assigned_Agent__c, Assigned_Agent__r.Name,
                   Session_Status__c, Active__c
            FROM Channel__c
            ORDER BY Name ASC
            LIMIT 200
        ];
    }

    /** Returns the login QR (data-URL or QR string) for in-Salesforce scanning. */
    @AuraEnabled
    public static String getQr(Id channelId) {
        Channel__c ch = loadChannel(channelId);
        try {
            return MaxDootHeydootClient.getQr(ch.Heydoot_Channel_Id__c);
        } catch (Exception e) {
            throw new AuraHandledException('Could not fetch QR: ' + e.getMessage());
        }
    }

    /** Polls heydoot for the live session status and persists it on the channel. */
    @AuraEnabled
    public static String refreshStatus(Id channelId) {
        Channel__c ch = loadChannel(channelId);
        String status;
        try {
            status = MaxDootHeydootClient.getStatus(ch.Heydoot_Channel_Id__c);
        } catch (Exception e) {
            throw new AuraHandledException('Could not fetch status: ' + e.getMessage());
        }
        if (ch.Session_Status__c != status) {
            update new Channel__c(Id = ch.Id, Session_Status__c = status);
        }
        return status;
    }

    private static Channel__c loadChannel(Id channelId) {
        List<Channel__c> chs = [
            SELECT Id, Heydoot_Channel_Id__c, Session_Status__c
            FROM Channel__c WHERE Id = :channelId LIMIT 1
        ];
        if (chs.isEmpty()) {
            throw new AuraHandledException('Channel not found.');
        }
        if (String.isBlank(chs[0].Heydoot_Channel_Id__c)) {
            throw new AuraHandledException('Channel has no heydoot Channel Id configured.');
        }
        return chs[0];
    }
}
