/**
 * Resolves an inbound customer number to a Contact/Lead and decides which agent
 * should own the conversation based on the channel's routing scope.
 */
public with sharing class MaxDootRouting {

    public class Match {
        public Id contactId;
        public Id leadId;
    }

    /**
     * Bulk match a set of phone numbers to Contacts (preferred) or Leads.
     * Matching is a digits-only suffix compare to tolerate formatting differences.
     */
    public static Map<String, Match> matchNumbers(Set<String> numbers) {
        Map<String, Match> result = new Map<String, Match>();
        Map<String, String> normToRaw = new Map<String, String>();
        for (String n : numbers) {
            if (String.isBlank(n)) continue;
            result.put(n, new Match());
            normToRaw.put(digits(n), n);
        }
        if (normToRaw.isEmpty()) return result;

        // Contacts first.
        for (Contact c : [
            SELECT Id, Phone, MobilePhone
            FROM Contact
            WHERE Phone != null OR MobilePhone != null
            LIMIT 2000
        ]) {
            assignIfMatch(result, normToRaw, digits(c.MobilePhone), c.Id, true);
            assignIfMatch(result, normToRaw, digits(c.Phone), c.Id, true);
        }
        // Leads for any still unmatched.
        for (Lead l : [
            SELECT Id, Phone, MobilePhone, IsConverted
            FROM Lead
            WHERE IsConverted = false AND (Phone != null OR MobilePhone != null)
            LIMIT 2000
        ]) {
            assignIfMatch(result, normToRaw, digits(l.MobilePhone), l.Id, false);
            assignIfMatch(result, normToRaw, digits(l.Phone), l.Id, false);
        }
        return result;
    }

    private static void assignIfMatch(Map<String, Match> result, Map<String, String> normToRaw,
                                      String recDigits, Id recId, Boolean isContact) {
        if (String.isBlank(recDigits)) return;
        for (String norm : normToRaw.keySet()) {
            if (suffixEquals(norm, recDigits)) {
                Match m = result.get(normToRaw.get(norm));
                if (isContact && m.contactId == null) {
                    m.contactId = recId;
                } else if (!isContact && m.leadId == null && m.contactId == null) {
                    m.leadId = recId;
                }
            }
        }
    }

    /** Decide the owning agent for a conversation given its channel. */
    public static Id resolveOwner(Channel__c channel) {
        if (channel == null) return null;
        if (channel.Scope__c == 'Agent' && channel.Assigned_Agent__c != null) {
            return channel.Assigned_Agent__c;
        }
        // Team/Org scopes leave ownership unassigned for the inbox to pick up.
        return null;
    }

    private static String digits(String s) {
        return s == null ? '' : s.replaceAll('[^0-9]', '');
    }

    /** True when the shorter of the two is a suffix of the longer (>= 8 digits). */
    private static Boolean suffixEquals(String a, String b) {
        if (String.isBlank(a) || String.isBlank(b)) return false;
        if (a == b) return true;
        Integer len = Math.min(a.length(), b.length());
        if (len < 8) return false;
        return a.endsWith(b) || b.endsWith(a);
    }
}
