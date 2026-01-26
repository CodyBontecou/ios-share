// Export service for creating ZIP archives of user images

import { Database, Image } from './database';

export interface ExportManifest {
  export_date: string;
  image_count: number;
  total_size_bytes: number;
  images: Array<{
    id: string;
    filename: string;
    size_bytes: number;
    content_type: string;
    created_at: number;
  }>;
}

export class ExportService {
  constructor(
    private db: Database,
    private r2Bucket: R2Bucket
  ) {}

  /**
   * Process export job: fetch images, create ZIP, and store in R2
   */
  async processExportJob(jobId: string, userId: string): Promise<void> {
    try {
      // Get all images for user
      const images = await this.getAllUserImages(userId);

      if (images.length === 0) {
        await this.db.updateExportJob(
          jobId,
          'failed',
          0,
          0,
          undefined,
          undefined,
          'No images found to export'
        );
        return;
      }

      // Create ZIP archive
      const { zipBlob, totalSize } = await this.createZipArchive(images);

      // Upload ZIP to R2
      const zipKey = `exports/${jobId}.zip`;
      await this.r2Bucket.put(zipKey, zipBlob, {
        httpMetadata: {
          contentType: 'application/zip',
        },
        customMetadata: {
          jobId,
          userId,
          imageCount: images.length.toString(),
        },
      });

      // Calculate expiration (24 hours from now)
      const expiresAt = Date.now() + (24 * 60 * 60 * 1000);

      // Update job status
      await this.db.updateExportJob(
        jobId,
        'completed',
        images.length,
        totalSize,
        zipKey,
        expiresAt
      );
    } catch (error) {
      console.error('Export job failed:', error);
      await this.db.updateExportJob(
        jobId,
        'failed',
        0,
        0,
        undefined,
        undefined,
        error instanceof Error ? error.message : 'Unknown error'
      );
    }
  }

  /**
   * Get all images for a user
   */
  private async getAllUserImages(userId: string): Promise<Image[]> {
    const allImages: Image[] = [];
    let offset = 0;
    const limit = 100;

    while (true) {
      const batch = await this.db.getImagesByUserId(userId, limit, offset);
      if (batch.length === 0) break;

      allImages.push(...batch);
      offset += limit;

      if (batch.length < limit) break;
    }

    return allImages;
  }

  /**
   * Create ZIP archive from images
   */
  private async createZipArchive(images: Image[]): Promise<{ zipBlob: Blob; totalSize: number }> {
    // For Cloudflare Workers, we need to use a streaming approach or a library
    // Since we don't have native ZIP support, we'll use a simple approach:
    // Create a ZIP file structure manually or use a lightweight library

    // For now, we'll create a simple implementation that stores files with manifest
    // In production, you'd want to use a proper ZIP library like fflate or jszip

    const files: Array<{ name: string; data: ArrayBuffer }> = [];
    let totalSize = 0;

    // Fetch all images from R2
    for (const image of images) {
      try {
        const object = await this.r2Bucket.get(image.r2_key);
        if (object) {
          const data = await object.arrayBuffer();
          files.push({
            name: image.filename,
            data,
          });
          totalSize += data.byteLength;
        }
      } catch (error) {
        console.error(`Failed to fetch image ${image.r2_key}:`, error);
      }
    }

    // Create manifest
    const manifest: ExportManifest = {
      export_date: new Date().toISOString(),
      image_count: images.length,
      total_size_bytes: totalSize,
      images: images.map(img => ({
        id: img.id,
        filename: img.filename,
        size_bytes: img.size_bytes,
        content_type: img.content_type,
        created_at: img.created_at,
      })),
    };

    // Create a simple ZIP-like structure using custom format
    // NOTE: For production, replace this with a proper ZIP library
    const zipBlob = await this.createSimpleArchive(files, manifest);

    return { zipBlob, totalSize };
  }

  /**
   * Create a simple archive format (placeholder for proper ZIP implementation)
   * In production, use fflate or jszip library
   */
  private async createSimpleArchive(
    files: Array<{ name: string; data: ArrayBuffer }>,
    manifest: ExportManifest
  ): Promise<Blob> {
    // This is a simplified implementation
    // In production, you should use a proper ZIP library like fflate

    const parts: (Uint8Array | string)[] = [];

    // Add manifest as first file
    const manifestJson = JSON.stringify(manifest, null, 2);
    parts.push(new TextEncoder().encode(`MANIFEST.JSON\n${manifestJson}\n\n`));

    // Add each file
    for (const file of files) {
      parts.push(new TextEncoder().encode(`FILE:${file.name}\n`));
      parts.push(new Uint8Array(file.data));
      parts.push(new TextEncoder().encode('\n\n'));
    }

    return new Blob(parts);
  }

  /**
   * Get download URL for completed export
   */
  async getDownloadUrl(jobId: string, baseUrl: string): Promise<string> {
    return `${baseUrl}/api/export/${jobId}/download`;
  }

  /**
   * Cleanup expired exports from R2
   */
  async cleanupExpiredExports(): Promise<void> {
    // This would be called by a scheduled worker/cron
    await this.db.cleanupExpiredExports();
  }
}
