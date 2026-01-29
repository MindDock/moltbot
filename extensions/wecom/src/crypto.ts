/**
 * WeCom message encryption/decryption utilities
 * @see https://developer.work.weixin.qq.com/document/path/90307
 */

import crypto from "node:crypto";

/**
 * Verify WeCom webhook signature
 */
export function verifySignature(
  token: string,
  timestamp: string,
  nonce: string,
  echostr: string,
  signature: string,
): boolean {
  const arr = [token, timestamp, nonce, echostr].sort();
  const str = arr.join("");
  const sha1 = crypto.createHash("sha1").update(str).digest("hex");
  return sha1 === signature;
}

/**
 * Verify message signature (for incoming messages)
 */
export function verifyMsgSignature(
  token: string,
  timestamp: string,
  nonce: string,
  encryptedMsg: string,
  signature: string,
): boolean {
  const arr = [token, timestamp, nonce, encryptedMsg].sort();
  const str = arr.join("");
  const sha1 = crypto.createHash("sha1").update(str).digest("hex");
  return sha1 === signature;
}

/**
 * Decode Base64 encoding key to buffer
 */
function decodeAesKey(encodingAesKey: string): Buffer {
  return Buffer.from(encodingAesKey + "=", "base64");
}

/**
 * PKCS#7 unpadding
 */
function pkcs7Unpad(buffer: Buffer): Buffer {
  const padLen = buffer[buffer.length - 1];
  if (padLen < 1 || padLen > 32) {
    return buffer;
  }
  return buffer.subarray(0, buffer.length - padLen);
}

/**
 * PKCS#7 padding
 */
function pkcs7Pad(buffer: Buffer, blockSize = 32): Buffer {
  const padLen = blockSize - (buffer.length % blockSize);
  const padding = Buffer.alloc(padLen, padLen);
  return Buffer.concat([buffer, padding]);
}

/**
 * Decrypt WeCom message
 */
export function decryptMessage(
  encryptedMsg: string,
  encodingAesKey: string,
  corpId: string,
): string {
  const aesKey = decodeAesKey(encodingAesKey);
  const iv = aesKey.subarray(0, 16);

  const decipher = crypto.createDecipheriv("aes-256-cbc", aesKey, iv);
  decipher.setAutoPadding(false);

  const encrypted = Buffer.from(encryptedMsg, "base64");
  let decrypted = Buffer.concat([decipher.update(encrypted), decipher.final()]);
  decrypted = pkcs7Unpad(decrypted);

  // Message format: random(16) + msgLen(4) + msg + corpId
  const msgLen = decrypted.readUInt32BE(16);
  const msg = decrypted.subarray(20, 20 + msgLen).toString("utf8");
  const extractedCorpId = decrypted.subarray(20 + msgLen).toString("utf8");

  if (extractedCorpId !== corpId) {
    throw new Error(`CorpID mismatch: expected ${corpId}, got ${extractedCorpId}`);
  }

  return msg;
}

/**
 * Encrypt WeCom message for reply
 */
export function encryptMessage(
  msg: string,
  encodingAesKey: string,
  corpId: string,
): string {
  const aesKey = decodeAesKey(encodingAesKey);
  const iv = aesKey.subarray(0, 16);

  const random = crypto.randomBytes(16);
  const msgBuf = Buffer.from(msg, "utf8");
  const msgLenBuf = Buffer.alloc(4);
  msgLenBuf.writeUInt32BE(msgBuf.length, 0);
  const corpIdBuf = Buffer.from(corpId, "utf8");

  const plaintext = Buffer.concat([random, msgLenBuf, msgBuf, corpIdBuf]);
  const padded = pkcs7Pad(plaintext);

  const cipher = crypto.createCipheriv("aes-256-cbc", aesKey, iv);
  cipher.setAutoPadding(false);
  const encrypted = Buffer.concat([cipher.update(padded), cipher.final()]);

  return encrypted.toString("base64");
}

/**
 * Generate message signature for reply
 */
export function generateSignature(
  token: string,
  timestamp: string,
  nonce: string,
  encryptedMsg: string,
): string {
  const arr = [token, timestamp, nonce, encryptedMsg].sort();
  const str = arr.join("");
  return crypto.createHash("sha1").update(str).digest("hex");
}
