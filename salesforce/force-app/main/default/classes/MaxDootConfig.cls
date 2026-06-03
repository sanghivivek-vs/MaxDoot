/**
 * Central access to MaxDoot configuration stored in MaxDoot_Config__mdt (record "Default").
 * Endpoint base URL + transport live in the `heydoot` Named Credential; this holds the
 * path templates, the outbound API key and the inbound shared token.
 */
public with sharing class MaxDootConfig {
    @TestVisible private static MaxDoot_Config__mdt override;

    public static MaxDoot_Config__mdt get() {
        if (override != null) {
            return override;
        }
        MaxDoot_Config__mdt cfg = MaxDoot_Config__mdt.getInstance('Default');
        if (cfg == null) {
            // Defensive fallback so the app degrades gracefully if the record is missing.
            cfg = new MaxDoot_Config__mdt(
                Send_Path__c = '/v1/channels/{channelId}/messages',
                QR_Path__c = '/v1/channels/{channelId}/qr',
                Status_Path__c = '/v1/channels/{channelId}/status'
            );
        }
        return cfg;
    }

    /** The Named Credential reference all heydoot callouts go through. */
    public static String namedCredential() {
        return 'callout:heydoot';
    }
}
