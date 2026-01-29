/**
 * Feishu event decryption utilities
 * @see https://open.feishu.cn/document/ukTMukTMukTM/uYDNxYjL2QTM24iN0EjN/event-subscription-configure-/encrypt-key-encryption-configuration-case
 */

import crypto from "node:crypto";

/**
 * Decrypt Feishu event payload
 * Feishu uses AES-256-CBC with the encrypt_key as the key
 */
export function decryptEvent(encrypted: string, encryptKey: string): string {
  const encryptedBuffer = Buffer.from(encrypted, "base64");

  // Derive key using SHA256 of encryptKey
  const key = crypto.createHash("sha256").update(encryptKey).digest();

  // First 16 bytes are the IV
  const iv = encryptedBuffer.subarray(0, 16);
  const ciphertext = encryptedBuffer.subarray(16);

  const decipher = crypto.createDecipheriv("aes-256-cbc", key, iv);
  let decrypted = decipher.update(ciphertext);
  decrypted = Buffer.concat([decrypted, decipher.final()]);

  return decrypted.toString("utf8");
}

/**
 * Verify event signature (v2 events)
 * signature = sha256(timestamp + nonce + encrypt_key + body)
 */
export function verifySignature(
  timestamp: string,
  nonce: string,
  encryptKey: string,
  body: string,
  signature: string,
): boolean {
  const content = timestamp + nonce + encryptKey + body;
  const computed = crypto.createHash("sha256").update(content).digest("hex");
  return computed === signature;
}
