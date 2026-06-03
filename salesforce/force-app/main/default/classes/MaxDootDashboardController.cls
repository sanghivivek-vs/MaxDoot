/**
 * Supplies KPI aggregates for the MaxDoot dashboard LWC.
 */
public with sharing class MaxDootDashboardController {

    public class Stats {
        @AuraEnabled public Integer openConversations;
        @AuraEnabled public Integer unassigned;
        @AuraEnabled public Integer unread;
        @AuraEnabled public Integer messagesToday;
        @AuraEnabled public Integer connectedChannels;
    }

    @AuraEnabled(cacheable=true)
    public static Stats getStats() {
        Stats s = new Stats();
        s.openConversations = [SELECT COUNT() FROM Conversation__c WHERE Status__c = 'Open'];
        s.unassigned = [
            SELECT COUNT() FROM Conversation__c WHERE Status__c = 'Open' AND Owner_Agent__c = null
        ];
        AggregateResult ar = [
            SELECT SUM(Unread_Count__c) total FROM Conversation__c WHERE Status__c = 'Open'
        ];
        Object total = ar.get('total');
        s.unread = total == null ? 0 : ((Decimal) total).intValue();
        s.messagesToday = [SELECT COUNT() FROM Message__c WHERE CreatedDate = TODAY];
        s.connectedChannels = [
            SELECT COUNT() FROM Channel__c WHERE Active__c = true AND Session_Status__c = 'Connected'
        ];
        return s;
    }
}
