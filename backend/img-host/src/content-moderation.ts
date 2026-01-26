// Content moderation utilities for abuse prevention

export type FlagType = 'nsfw' | 'copyright' | 'malware' | 'suspicious';
export type AbuseReason = 'nsfw' | 'copyright' | 'malware' | 'spam' | 'other';

export interface ContentFlagResult {
  flagged: boolean;
  flags: {
    type: FlagType;
    confidence: number;
    reason: string;
  }[];
}

export interface AbuseReport {
  id: string;
  reported_image_id: string;
  reported_user_id: string;
  reporter_user_id: string | null;
  reporter_ip: string | null;
  reason: AbuseReason;
  description: string | null;
  status: 'pending' | 'reviewing' | 'resolved' | 'dismissed';
  created_at: number;
}

export class ContentModerator {
  constructor(private db: D1Database) {}

  /**
   * Validate file type beyond just MIME type
   * Checks magic bytes to detect actual file type
   */
  async validateFileType(
    file: File,
    allowedTypes: string[] = ['image/jpeg', 'image/png', 'image/gif', 'image/webp']
  ): Promise<{ valid: boolean; detectedType: string | null; reason?: string }> {
    // Check MIME type first
    if (!allowedTypes.includes(file.type)) {
      return {
        valid: false,
        detectedType: file.type,
        reason: `MIME type ${file.type} not allowed`,
      };
    }

    try {
      // Read first few bytes to check magic bytes
      const buffer = await file.slice(0, 12).arrayBuffer();
      const bytes = new Uint8Array(buffer);

      // Check magic bytes for common image formats
      const magicBytes = this.detectFileTypeByMagicBytes(bytes);

      if (!magicBytes) {
        return {
          valid: false,
          detectedType: null,
          reason: 'Could not detect file type from magic bytes',
        };
      }

      // Verify magic bytes match MIME type
      if (!this.mimeMatchesMagicBytes(file.type, magicBytes)) {
        return {
          valid: false,
          detectedType: magicBytes,
          reason: `MIME type ${file.type} does not match detected type ${magicBytes}`,
        };
      }

      return {
        valid: true,
        detectedType: magicBytes,
      };
    } catch (error) {
      console.error('Error validating file type:', error);
      return {
        valid: false,
        detectedType: null,
        reason: 'Error reading file bytes',
      };
    }
  }

  /**
   * Detect file type by magic bytes
   */
  private detectFileTypeByMagicBytes(bytes: Uint8Array): string | null {
    // JPEG: FF D8 FF
    if (bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff) {
      return 'image/jpeg';
    }

    // PNG: 89 50 4E 47 0D 0A 1A 0A
    if (
      bytes[0] === 0x89 &&
      bytes[1] === 0x50 &&
      bytes[2] === 0x4e &&
      bytes[3] === 0x47 &&
      bytes[4] === 0x0d &&
      bytes[5] === 0x0a &&
      bytes[6] === 0x1a &&
      bytes[7] === 0x0a
    ) {
      return 'image/png';
    }

    // GIF: 47 49 46 38 (GIF8)
    if (
      bytes[0] === 0x47 &&
      bytes[1] === 0x49 &&
      bytes[2] === 0x46 &&
      bytes[3] === 0x38
    ) {
      return 'image/gif';
    }

    // WebP: RIFF ... WEBP
    if (
      bytes[0] === 0x52 &&
      bytes[1] === 0x49 &&
      bytes[2] === 0x46 &&
      bytes[3] === 0x46 &&
      bytes[8] === 0x57 &&
      bytes[9] === 0x45 &&
      bytes[10] === 0x42 &&
      bytes[11] === 0x50
    ) {
      return 'image/webp';
    }

    // Executable detection (simple check for common malware)
    // Windows PE: MZ
    if (bytes[0] === 0x4d && bytes[1] === 0x5a) {
      return 'application/x-msdownload';
    }

    // ELF: 7F 45 4C 46
    if (
      bytes[0] === 0x7f &&
      bytes[1] === 0x45 &&
      bytes[2] === 0x4c &&
      bytes[3] === 0x46
    ) {
      return 'application/x-elf';
    }

    return null;
  }

  /**
   * Check if MIME type matches detected magic bytes
   */
  private mimeMatchesMagicBytes(mimeType: string, detectedType: string): boolean {
    // Exact match
    if (mimeType === detectedType) {
      return true;
    }

    // Handle variants (e.g., image/jpg vs image/jpeg)
    if (mimeType === 'image/jpg' && detectedType === 'image/jpeg') {
      return true;
    }

    return false;
  }

  /**
   * Scan image for suspicious patterns (basic malware detection)
   */
  async scanForMalware(file: File): Promise<ContentFlagResult> {
    const flags: { type: FlagType; confidence: number; reason: string }[] = [];

    try {
      // Check file extension
      const filename = file.name.toLowerCase();
      const suspiciousExtensions = ['.exe', '.bat', '.cmd', '.com', '.scr', '.vbs', '.js'];

      for (const ext of suspiciousExtensions) {
        if (filename.endsWith(ext)) {
          flags.push({
            type: 'malware',
            confidence: 1.0,
            reason: `Suspicious file extension: ${ext}`,
          });
        }
      }

      // Check for double extensions (e.g., image.jpg.exe)
      const parts = filename.split('.');
      if (parts.length > 2) {
        const secondLastExt = `.${parts[parts.length - 2]}`;
        if (suspiciousExtensions.includes(secondLastExt)) {
          flags.push({
            type: 'malware',
            confidence: 0.9,
            reason: 'Double extension detected',
          });
        }
      }

      // Validate file type
      const typeValidation = await this.validateFileType(file);
      if (!typeValidation.valid) {
        flags.push({
          type: 'malware',
          confidence: 0.8,
          reason: typeValidation.reason || 'Invalid file type',
        });
      }

      // Check for executable magic bytes in what claims to be an image
      if (
        typeValidation.detectedType === 'application/x-msdownload' ||
        typeValidation.detectedType === 'application/x-elf'
      ) {
        flags.push({
          type: 'malware',
          confidence: 1.0,
          reason: 'Executable file disguised as image',
        });
      }

      return {
        flagged: flags.length > 0,
        flags,
      };
    } catch (error) {
      console.error('Error scanning for malware:', error);
      return {
        flagged: false,
        flags: [],
      };
    }
  }

  /**
   * Flag content for review
   */
  async flagContent(
    imageId: string,
    flagType: FlagType,
    confidence: number,
    flaggedBy: string = 'system',
    metadata?: Record<string, any>
  ): Promise<void> {
    const id = crypto.randomUUID();
    const now = Date.now();

    await this.db
      .prepare(
        `INSERT INTO content_flags (id, image_id, flag_type, confidence_score, flagged_by, metadata, created_at)
         VALUES (?, ?, ?, ?, ?, ?, ?)`
      )
      .bind(
        id,
        imageId,
        flagType,
        confidence,
        flaggedBy,
        metadata ? JSON.stringify(metadata) : null,
        now
      )
      .run();
  }

  /**
   * Get content flags for an image
   */
  async getContentFlags(imageId: string): Promise<
    {
      id: string;
      flag_type: FlagType;
      confidence_score: number;
      flagged_by: string;
      metadata: string | null;
      created_at: number;
    }[]
  > {
    const result = await this.db
      .prepare('SELECT * FROM content_flags WHERE image_id = ? ORDER BY created_at DESC')
      .bind(imageId)
      .all<{
        id: string;
        flag_type: FlagType;
        confidence_score: number;
        flagged_by: string;
        metadata: string | null;
        created_at: number;
      }>();

    return result.results || [];
  }

  /**
   * Submit an abuse report
   */
  async submitAbuseReport(
    imageId: string,
    reportedUserId: string,
    reporterUserId: string | null,
    reporterIp: string | null,
    reason: AbuseReason,
    description: string | null
  ): Promise<AbuseReport> {
    const id = crypto.randomUUID();
    const now = Date.now();

    await this.db
      .prepare(
        `INSERT INTO abuse_reports (id, reported_image_id, reported_user_id, reporter_user_id, reporter_ip, reason, description, status, created_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, 'pending', ?)`
      )
      .bind(
        id,
        imageId,
        reportedUserId,
        reporterUserId,
        reporterIp,
        reason,
        description,
        now
      )
      .run();

    return {
      id,
      reported_image_id: imageId,
      reported_user_id: reportedUserId,
      reporter_user_id: reporterUserId,
      reporter_ip: reporterIp,
      reason,
      description,
      status: 'pending',
      created_at: now,
    };
  }

  /**
   * Get abuse reports for an image
   */
  async getAbuseReports(
    imageId: string
  ): Promise<AbuseReport[]> {
    const result = await this.db
      .prepare(
        'SELECT * FROM abuse_reports WHERE reported_image_id = ? ORDER BY created_at DESC'
      )
      .bind(imageId)
      .all<AbuseReport>();

    return result.results || [];
  }

  /**
   * Get pending abuse reports (for admin review)
   */
  async getPendingAbuseReports(limit = 50): Promise<AbuseReport[]> {
    const result = await this.db
      .prepare(
        'SELECT * FROM abuse_reports WHERE status = ? ORDER BY created_at DESC LIMIT ?'
      )
      .bind('pending', limit)
      .all<AbuseReport>();

    return result.results || [];
  }

  /**
   * Update abuse report status
   */
  async updateAbuseReportStatus(
    reportId: string,
    status: 'reviewing' | 'resolved' | 'dismissed',
    reviewedBy: string,
    resolutionNotes?: string
  ): Promise<void> {
    const now = Date.now();

    await this.db
      .prepare(
        'UPDATE abuse_reports SET status = ?, reviewed_at = ?, reviewed_by = ?, resolution_notes = ? WHERE id = ?'
      )
      .bind(status, now, reviewedBy, resolutionNotes || null, reportId)
      .run();
  }

  /**
   * Check for unusual upload patterns (potential abuse detection)
   */
  async detectUnusualUploadPattern(userId: string): Promise<{
    suspicious: boolean;
    reasons: string[];
  }> {
    const reasons: string[] = [];
    const now = Date.now();
    const oneHourAgo = now - 60 * 60 * 1000;
    const oneDayAgo = now - 24 * 60 * 60 * 1000;

    // Check upload rate in last hour
    const recentUploads = await this.db
      .prepare(
        'SELECT COUNT(*) as count FROM images WHERE user_id = ? AND created_at > ?'
      )
      .bind(userId, oneHourAgo)
      .first<{ count: number }>();

    if (recentUploads && recentUploads.count > 50) {
      reasons.push(`High upload rate: ${recentUploads.count} uploads in last hour`);
    }

    // Check for identical file sizes (potential spam)
    const identicalSizes = await this.db
      .prepare(
        `SELECT size_bytes, COUNT(*) as count
         FROM images
         WHERE user_id = ? AND created_at > ?
         GROUP BY size_bytes
         HAVING count > 10`
      )
      .bind(userId, oneDayAgo)
      .first<{ count: number }>();

    if (identicalSizes) {
      reasons.push(`Identical file sizes: ${identicalSizes.count} files with same size`);
    }

    // Check for rapid sequential uploads (bot-like behavior)
    const sequentialUploads = await this.db
      .prepare(
        `SELECT created_at FROM images
         WHERE user_id = ?
         ORDER BY created_at DESC
         LIMIT 10`
      )
      .bind(userId)
      .all<{ created_at: number }>();

    if (sequentialUploads.results && sequentialUploads.results.length >= 10) {
      const timestamps = sequentialUploads.results.map(r => r.created_at);
      const intervals = [];
      for (let i = 0; i < timestamps.length - 1; i++) {
        intervals.push(timestamps[i] - timestamps[i + 1]);
      }

      // If all intervals are very similar (within 1 second), it's suspicious
      const avgInterval = intervals.reduce((a, b) => a + b, 0) / intervals.length;
      const allSimilar = intervals.every(
        interval => Math.abs(interval - avgInterval) < 1000
      );

      if (allSimilar && avgInterval < 5000) {
        reasons.push('Bot-like upload pattern detected (too consistent)');
      }
    }

    return {
      suspicious: reasons.length > 0,
      reasons,
    };
  }
}
