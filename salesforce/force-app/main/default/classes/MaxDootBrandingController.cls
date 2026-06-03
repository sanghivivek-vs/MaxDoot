/**
 * Exposes MaxDoot branding + Contact Us details (from MaxDoot_Config__mdt) to the
 * About LWC, so the company name, tagline and support contacts are configurable
 * per deployment without code changes.
 */
public with sharing class MaxDootBrandingController {

    public class Branding {
        @AuraEnabled public String companyName;
        @AuraEnabled public String tagline;
        @AuraEnabled public String supportEmail;
        @AuraEnabled public String supportPhone;
        @AuraEnabled public String supportUrl;
    }

    @AuraEnabled(cacheable=true)
    public static Branding getBranding() {
        MaxDoot_Config__mdt cfg = MaxDootConfig.get();
        Branding b = new Branding();
        b.companyName = String.isNotBlank(cfg.Company_Name__c) ? cfg.Company_Name__c : 'MaxDoot';
        b.tagline = cfg.Tagline__c;
        b.supportEmail = clean(cfg.Support_Email__c);
        b.supportPhone = clean(cfg.Support_Phone__c);
        b.supportUrl = clean(cfg.Support_URL__c);
        return b;
    }

    /** Hide unconfigured placeholder values from the UI. */
    private static String clean(String value) {
        if (String.isBlank(value) || value.startsWith('REPLACE_WITH')) {
            return null;
        }
        return value;
    }
}
