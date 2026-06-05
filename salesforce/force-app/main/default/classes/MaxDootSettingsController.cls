/**
 * Backs the in-app MaxDoot Settings screen: read/update global config
 * (paths, inbound token, branding) without leaving Salesforce, surface the
 * public inbound webhook URL, and manage channels.
 *
 * Global settings live in the MaxDoot_Config__mdt 'Default' record, so writes
 * go through the Apex Metadata API (asynchronous deploy).
 */
public with sharing class MaxDootSettingsController {

    public class ChannelInfo {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String whatsAppNumber;
        @AuraEnabled public String heydootSessionId;
        @AuraEnabled public String scope;
        @AuraEnabled public String sessionStatus;
        @AuraEnabled public Boolean active;
        @AuraEnabled public Boolean hasToken;
    }

    public class Settings {
        @AuraEnabled public String companyName;
        @AuraEnabled public String tagline;
        @AuraEnabled public String supportEmail;
        @AuraEnabled public String supportPhone;
        @AuraEnabled public String supportUrl;
        @AuraEnabled public String sendPath;
        @AuraEnabled public String statusPath;
        @AuraEnabled public String inboundToken;
        @AuraEnabled public String webhookUrl;
        @AuraEnabled public List<ChannelInfo> channels;
    }

    @AuraEnabled
    public static Settings getSettings() {
        MaxDoot_Config__mdt cfg = MaxDootConfig.get();
        Settings s = new Settings();
        s.companyName = cfg.Company_Name__c;
        s.tagline = cfg.Tagline__c;
        s.supportEmail = strip(cfg.Support_Email__c);
        s.supportPhone = strip(cfg.Support_Phone__c);
        s.supportUrl = strip(cfg.Support_URL__c);
        s.sendPath = cfg.Send_Path__c;
        s.statusPath = cfg.Status_Path__c;
        s.inboundToken = strip(cfg.Inbound_Token__c);
        s.webhookUrl = inboundWebhookUrl();
        s.channels = listChannels();
        return s;
    }

    private static List<ChannelInfo> listChannels() {
        List<ChannelInfo> out = new List<ChannelInfo>();
        for (Channel__c c : [
            SELECT Id, Name, WhatsApp_Number__c, Heydoot_Channel_Id__c, Scope__c,
                   Session_Status__c, Active__c, Bearer_Token__c
            FROM Channel__c ORDER BY Name ASC LIMIT 200
        ]) {
            ChannelInfo ci = new ChannelInfo();
            ci.id = c.Id;
            ci.name = c.Name;
            ci.whatsAppNumber = c.WhatsApp_Number__c;
            ci.heydootSessionId = c.Heydoot_Channel_Id__c;
            ci.scope = c.Scope__c;
            ci.sessionStatus = c.Session_Status__c;
            ci.active = c.Active__c;
            ci.hasToken = String.isNotBlank(c.Bearer_Token__c);
            out.add(ci);
        }
        return out;
    }

    /** Build the public inbound webhook URL from the MaxDoot Inbound Site, if present. */
    @TestVisible
    private static String inboundWebhookUrl() {
        try {
            for (DomainSite ds : [SELECT Domain.Domain, PathPrefix FROM DomainSite WHERE Site.Name = 'MaxDoot_Inbound' LIMIT 1]) {
                String prefix = ds.PathPrefix == null ? '' : ds.PathPrefix;
                return 'https://' + ds.Domain.Domain + prefix + '/services/apexrest/maxdoot/inbound';
            }
        } catch (Exception ignored) {
            // Site object may be unavailable; fall through.
        }
        return null;
    }

    @AuraEnabled
    public static void updateBranding(String companyName, String tagline,
            String supportEmail, String supportPhone, String supportUrl) {
        deployConfig(new Map<String, Object>{
            'Company_Name__c' => companyName,
            'Tagline__c' => tagline,
            'Support_Email__c' => supportEmail,
            'Support_Phone__c' => supportPhone,
            'Support_URL__c' => supportUrl
        });
    }

    @AuraEnabled
    public static void updateConnection(String sendPath, String statusPath) {
        deployConfig(new Map<String, Object>{
            'Send_Path__c' => sendPath,
            'Status_Path__c' => statusPath
        });
    }

    /** Generate a new shared secret for the heydoot -> Salesforce webhook and return it. */
    @AuraEnabled
    public static String regenerateInboundToken() {
        String token = 'mdoot_' + EncodingUtil.convertToHex(Crypto.generateAesKey(256));
        deployConfig(new Map<String, Object>{ 'Inbound_Token__c' => token });
        return token;
    }

    /** Create or update a channel. Bearer token is only written when provided (never blanked). */
    @AuraEnabled
    public static Id saveChannel(Id channelId, String name, String whatsAppNumber,
            String heydootSessionId, String scope, Boolean active, String bearerToken) {
        Channel__c c = new Channel__c(
            Name = name,
            WhatsApp_Number__c = whatsAppNumber,
            Heydoot_Channel_Id__c = heydootSessionId,
            Scope__c = String.isBlank(scope) ? 'Org' : scope,
            Active__c = active == null ? true : active
        );
        if (channelId != null) {
            c.Id = channelId;
        }
        if (String.isNotBlank(bearerToken)) {
            c.Bearer_Token__c = bearerToken;
        }
        upsert c;
        return c.Id;
    }

    @AuraEnabled
    public static String refreshChannelStatus(Id channelId) {
        return MaxDootChannelController.refreshStatus(channelId);
    }

    private static void deployConfig(Map<String, Object> vals) {
        Metadata.CustomMetadata cm = new Metadata.CustomMetadata();
        cm.fullName = 'MaxDoot_Config.Default';
        cm.label = 'Default';
        for (String field : vals.keySet()) {
            Metadata.CustomMetadataValue v = new Metadata.CustomMetadataValue();
            v.field = field;
            v.value = vals.get(field);
            cm.values.add(v);
        }
        Metadata.DeployContainer dc = new Metadata.DeployContainer();
        dc.addMetadata(cm);
        Metadata.Operations.enqueueDeployment(dc, null);
    }

    private static String strip(String value) {
        return (String.isBlank(value) || value.startsWith('REPLACE_WITH')) ? null : value;
    }
}
