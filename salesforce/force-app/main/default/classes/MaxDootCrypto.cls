/**
 * Application-level AES-256 encryption for MaxDoot conversation content.
 *
 * Message bodies and the inbox preview snippet are stored as ciphertext at rest
 * (Shield Platform Encryption is not licensed on this org, and bodies are long-text
 * so the native Encrypted Text field type does not fit). Authorized agents see the
 * plaintext because read paths decrypt in-memory before returning to the UI.
 *
 * Key: a base64 AES-256 key in the Protected custom setting MaxDoot_Crypto__c.Key__c.
 * It is set once via script and never committed to source.
 *
 * Backward compatibility: values written before encryption (no ENC1: marker) are
 * returned as-is by decrypt(), so pre-existing rows remain readable.
 */
public with sharing class MaxDootCrypto {

    @TestVisible
    private static final String PREFIX = 'ENC1:';
    private static Blob keyCache;

    public class MaxDootCryptoException extends Exception {}

    private static Blob key() {
        if (keyCache == null) {
            MaxDoot_Crypto__c s = MaxDoot_Crypto__c.getOrgDefaults();
            if (s != null && String.isNotBlank(s.Key__c)) {
                keyCache = EncodingUtil.base64Decode(s.Key__c);
            } else if (Test.isRunningTest()) {
                // Tests don't see the org's custom-setting data; use an ephemeral key
                // (stable within a single test transaction so round-trips work).
                keyCache = Crypto.generateAesKey(256);
            } else {
                throw new MaxDootCryptoException(
                    'MaxDoot encryption key is not configured (MaxDoot_Crypto__c.Key__c).');
            }
        }
        return keyCache;
    }

    /** Encrypt plaintext. Null/empty pass through unchanged. Output: 'ENC1:' + base64. */
    public static String encrypt(String plain) {
        if (String.isEmpty(plain)) {
            return plain;
        }
        Blob enc = Crypto.encryptWithManagedIV('AES256', key(), Blob.valueOf(plain));
        return PREFIX + EncodingUtil.base64Encode(enc);
    }

    /** Decrypt a stored value. Null/empty and legacy (unmarked) plaintext pass through. */
    public static String decrypt(String stored) {
        if (String.isBlank(stored) || !stored.startsWith(PREFIX)) {
            return stored;
        }
        Blob dec = Crypto.decryptWithManagedIV(
            'AES256', key(), EncodingUtil.base64Decode(stored.substring(PREFIX.length())));
        return dec.toString();
    }

    /**
     * Encrypt for a fixed-length field: ciphertext is ~1.4x larger than plaintext, so
     * shrink the plaintext until the encrypted result fits maxLen (used for the 255-char
     * preview, which must hold the ciphertext, not the plaintext).
     */
    public static String encryptForField(String plain, Integer maxLen) {
        if (String.isEmpty(plain)) {
            return plain;
        }
        String s = plain;
        String enc = encrypt(s);
        while (enc.length() > maxLen && s.length() > 1) {
            s = s.substring(0, Math.max(1, (Integer) (s.length() * 0.7)));
            enc = encrypt(s);
        }
        return enc;
    }
}
