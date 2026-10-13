import Foundation
import CryptoKit
import WallpaperCore

@MainActor public enum VideoConverter {
    nonisolated public static func discoverFFmpeg() -> URL? {
        let paths = [Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("MediaTools/ffmpeg"),
                     URL(fileURLWithPath:"/opt/homebrew/bin/ffmpeg"), URL(fileURLWithPath:"/usr/local/bin/ffmpeg")]
        return paths.first { FileManager.default.isExecutableFile(atPath:$0.path) }
    }

    public static func prepare(folder: URL, cacheRoot: URL, ffmpeg: URL? = discoverFFmpeg(),
                               onProgress: ((String) -> Void)? = nil) async throws -> WallpaperProject {
        try Task.checkCancellation()
        let project = try WallpaperProject.load(folder:folder)
        let source = URL(fileURLWithPath:project.videoPath)
        if source.pathExtension.lowercased() == "mp4" {
            do {
                _ = try await MediaValidator.validate(url:source)
                try Task.checkCancellation()
                return project
            } catch is CancellationError { throw CancellationError() }
            catch { /* An MP4 container can still contain an unsupported codec. */ }
        }
        let fm = FileManager.default
        let values = try source.resourceValues(forKeys:[.fileSizeKey,.contentModificationDateKey])
        let manifestData = try Data(contentsOf:URL(fileURLWithPath:project.folderPath).appendingPathComponent("project.json"))
        guard var metadata = try JSONSerialization.jsonObject(with:manifestData) as? [String:Any] else {
            throw WallpaperError.message("project.json 格式不正确。")
        }
        var fingerprint = manifestData
        fingerprint.append(Data("\n\(source.path)\n\(values.fileSize ?? 0)\n\(values.contentModificationDate?.timeIntervalSince1970 ?? 0)\nh264-crf18-yuv420p-pad-aac-v3".utf8))
        let key = SHA256.hash(data:fingerprint).map { String(format:"%02x",$0) }.joined()
        let parent = cacheRoot.appendingPathComponent(key,isDirectory:true)
        let destination = parent.appendingPathComponent(URL(fileURLWithPath:project.folderPath).lastPathComponent,isDirectory:true)
        let cachedData = try? Data(contentsOf:destination.appendingPathComponent("project.json"))
        let cachedMetadata = cachedData.flatMap { (try? JSONSerialization.jsonObject(with:$0)) as? [String:Any] }
        if cachedMetadata?["convertedFingerprint"] as? String == key,
           let cached = try? WallpaperProject.load(folder:destination),
           (try? await MediaValidator.validate(url:URL(fileURLWithPath:cached.videoPath))) != nil {
            try Task.checkCancellation()
            return cached.identifyingSourceFolder(project.folderPath)
        }
        try Task.checkCancellation()
        guard let ffmpeg, fm.isExecutableFile(atPath:ffmpeg.path) else {
            throw WallpaperError.message("自动转换需要 FFmpeg。请安装 FFmpeg（Homebrew：brew install ffmpeg），或将可运行的工具放在 App 同级 MediaTools/ffmpeg。原文件已保留。")
        }
        onProgress?("正在转换为 MP4：\(project.title)（首次转换可能需要几分钟）")
        try fm.createDirectory(at:cacheRoot,withIntermediateDirectories:true)
        let staging = cacheRoot.appendingPathComponent(".conversion-"+UUID().uuidString,isDirectory:true)
        defer { try? fm.removeItem(at:staging) }
        let stagedFolder = staging.appendingPathComponent(destination.lastPathComponent,isDirectory:true)
        try fm.createDirectory(at:stagedFolder,withIntermediateDirectories:true)
        let videoName = "wallpaper-"+key+".mp4"
        let output = stagedFolder.appendingPathComponent(videoName)
        let result = try await SteamRunner.run(executable:ffmpeg, arguments:[
            "-nostdin","-hide_banner","-loglevel","error","-n","-i",source.path,
            "-map","0:v:0","-map","0:a:0?","-c:a","aac","-b:a","192k","-sn","-dn","-c:v","libx264","-preset","medium",
            "-crf","18","-vf","pad=ceil(iw/2)*2:ceil(ih/2)*2","-pix_fmt","yuv420p","-threads","2","-fps_mode","passthrough",
            "-movflags","+faststart",output.path
        ], timeout:3600, outputLimit:16384)
        try Task.checkCancellation()
        guard result.exitCode == 0 else {
            throw WallpaperError.message("视频转换失败，原文件已保留。\n"+String(result.output.suffix(1500)))
        }
        _ = try await MediaValidator.validate(url:output)
        try Task.checkCancellation()
        metadata["type"] = "video"; metadata["file"] = videoName
        metadata["convertedFrom"] = source.path
        metadata["convertedFingerprint"] = key
        metadata.removeValue(forKey:"preview")
        if let path = project.previewPath {
            let preview = URL(fileURLWithPath:path)
            let name = "preview" + (preview.pathExtension.isEmpty ? "" : "."+preview.pathExtension)
            try fm.copyItem(at:preview,to:stagedFolder.appendingPathComponent(name))
            metadata["preview"] = name
        }
        try JSONSerialization.data(withJSONObject:metadata,options:[.sortedKeys]).write(to:stagedFolder.appendingPathComponent("project.json"),options:.atomic)
        _ = try WallpaperProject.load(folder:stagedFolder)
        try Task.checkCancellation()
        // Publish a complete project only after native decode succeeds.
        let backup = cacheRoot.appendingPathComponent(".backup-"+UUID().uuidString,isDirectory:true)
        let hadPrevious = fm.fileExists(atPath:parent.path)
        if hadPrevious { try fm.moveItem(at:parent,to:backup) }
        do { try fm.moveItem(at:staging,to:parent) }
        catch {
            if hadPrevious { try? fm.moveItem(at:backup,to:parent) }
            throw error
        }
        if hadPrevious { try? fm.removeItem(at:backup) }
        return try WallpaperProject.load(folder:destination).identifyingSourceFolder(project.folderPath)
    }
}
