// PictunesCore.swift
import Foundation
import UIKit
import Combine
import os
import UniformTypeIdentifiers


// MARK: - Models

public struct Music: Identifiable, Codable, Equatable {
    public var id = UUID()                  // 前端 SwiftUI 用的識別
    public let title: String
    public let composer: String
    public let start: Int
    public let end: Int
    public let link: String                 // 仍保留連結，作為回放或相容舊版
    public let backendMusicID: Int?         // 新增：後端的 music_id

    private enum CodingKeys: String, CodingKey {
        case title, composer, start, end, link
        case backendMusicID = "music_id"    // 若後端直接回傳 music 陣列，可自動解碼
    }
}


public struct SimilarItem: Identifiable, Codable, Equatable {
    public var id = UUID()
    public let imageUrl: URL
    public let score: Double
    public let label: String?
    public let style: String?
    public let filename: String?

    private enum CodingKeys: String, CodingKey {
        case imageUrl, score, label, style, filename
    }
}

public struct UploadResponse: Codable, Equatable {
    public let label: String
    public let music: [Music]
    public let similar: [SimilarItem]?
    public let videoUrl: URL?

    private enum CodingKeys: String, CodingKey {
        case label, music, similar, videoUrl
    }
}

// MARK: - Domain

public enum RecommendationDomain: String, Codable, CaseIterable {
    case anime
    case film
}

// MARK: - Debug state

public enum PictunesDebugState: Equatable {
    case idle
    case requesting(endpoint: String)
    case success(source: String, httpStatus: Int?, detail: String)
    case failure(message: String, httpStatus: Int?, dataSnippet: String?)
}

// MARK: - Service

public final class PictunesService: ObservableObject {
    public static let shared = PictunesService()

    public enum Mode { case live, mock, autoFallback }

    public var enableConsoleLog: Bool = true
    public var logRawUploadResponse: Bool = false

    public var publicImageRootPath: String = "/image"
    public var alternativeStaticRootPath: String = "/dataset"

    @Published public private(set) var debugState: PictunesDebugState = .idle {
        didSet { if enableConsoleLog { clog("STATE: \(debugSummary)") } }
    }
    @Published public private(set) var isHealthy: Bool = false {
        didSet { if enableConsoleLog { clog("HEALTH /health: \(isHealthy ? "OK" : "FAIL")") } }
    }
    @Published public private(set) var isDBHealthy: Bool = false {
        didSet { if enableConsoleLog { clog("HEALTH /dbcon_check: \(isDBHealthy ? "OK" : "FAIL")") } }
    }
    @Published public private(set) var lastHTTPStatus: Int? = nil {
        didSet { if enableConsoleLog, let code = lastHTTPStatus { clog("HTTP: \(code)") } }
    }
    @Published public private(set) var lastErrorMessage: String? = nil {
        didSet { if enableConsoleLog, let msg = lastErrorMessage { clog("ERROR: \(msg)") } }
    }
    @Published public private(set) var lastUsedMock: Bool = false {
        didSet { if enableConsoleLog, lastUsedMock { clog("SOURCE: MOCK") } }
    }

    public var lastRequestUsedMock: Bool { lastUsedMock }
    public var mode: Mode = .live

    private let logger = Logger(subsystem: "me.pictunes.app", category: "network")
    private static let defaultBaseURL = "https://api.pictunes.me"
    private var baseURL: URL = {
        if let raw = Bundle.main.object(forInfoDictionaryKey: "PictunesAPIBaseURL") as? String,
           let url = URL(string: raw) {
            return url
        }
        return URL(string: defaultBaseURL)!
    }()

    // Endpoints
    private var uploadEndpoint: URL { baseURL.appendingPathComponent("upload") }
    private var mediaMergerEndpoint: URL { baseURL.appendingPathComponent("media_merger") }
    private var healthEndpoint: URL { baseURL.appendingPathComponent("health") }
    private var dbconCheckEndpoint: URL { baseURL.appendingPathComponent("dbcon_check") }

    private lazy var urlSession: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 60
        cfg.timeoutIntervalForResource = 300
        return URLSession(configuration: cfg)
    }()

    private init() {
        if enableConsoleLog {
            clog("PictunesService initialized. BaseURL=\(apiBaseString) Mode=\(modeString)")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.healthCheck()
            self.dbConnectionCheck()
        }
    }

    public var apiBaseString: String { baseURL.absoluteString }
    public var modeString: String {
        switch mode { case .live: return "live"; case .mock: return "mock"; case .autoFallback: return "autoFallback" }
    }

    public var debugSummary: String {
        switch debugState {
        case .idle: return "Idle"
        case .requesting(let ep): return "Requesting \(ep)"
        case .success(let src, let code, let detail): return "Success [\(src)] HTTP \(code ?? -1) \(detail)"
        case .failure(let msg, let code, let snippet):
            let cut = snippet?.prefix(160) ?? ""
            return "Failure HTTP \(code ?? -1): \(msg) \(cut)"
        }
    }

    // MARK: - Health checks

    public func healthCheck() {
        var req = URLRequest(url: healthEndpoint)
        req.httpMethod = "GET"
        req.timeoutInterval = 120
        debugState = .requesting(endpoint: "/health")
        urlSession.dataTask(with: req) { _, resp, err in
            let ok = (resp as? HTTPURLResponse)?.statusCode == 200 && err == nil
            DispatchQueue.main.async {
                self.isHealthy = ok
                self.lastHTTPStatus = (resp as? HTTPURLResponse)?.statusCode
                if ok {
                    self.debugState = .success(source: "live", httpStatus: self.lastHTTPStatus, detail: "/health OK")
                    self.lastUsedMock = false
                    self.lastErrorMessage = nil
                } else {
                    self.debugState = .failure(message: err?.localizedDescription ?? "Health not 200", httpStatus: self.lastHTTPStatus, dataSnippet: nil)
                    self.lastErrorMessage = err?.localizedDescription
                }
            }
        }.resume()
    }

    public func dbConnectionCheck() {
        var req = URLRequest(url: dbconCheckEndpoint)
        req.httpMethod = "GET"
        req.timeoutInterval = 120
        debugState = .requesting(endpoint: "/dbcon_check")
        urlSession.dataTask(with: req) { _, resp, err in
            let ok = (resp as? HTTPURLResponse)?.statusCode == 200 && err == nil
            DispatchQueue.main.async {
                self.isDBHealthy = ok
                self.lastHTTPStatus = (resp as? HTTPURLResponse)?.statusCode
                if ok {
                    self.debugState = .success(source: "live", httpStatus: self.lastHTTPStatus, detail: "/dbcon_check OK")
                    self.lastUsedMock = false
                    self.lastErrorMessage = nil
                } else {
                    self.debugState = .failure(message: err?.localizedDescription ?? "DB check not 200", httpStatus: self.lastHTTPStatus, dataSnippet: nil)
                    self.lastErrorMessage = err?.localizedDescription
                }
            }
        }.resume()
    }

    // MARK: - Upload API（第一次或第二次辨認都共用）

    public func upload(image: UIImage,
                       domain: RecommendationDomain,
                       completion: @escaping (Result<UploadResponse, Error>) -> Void) {
        switch mode {
        case .mock:
            lastUsedMock = true
            debugState = .requesting(endpoint: "/upload [mock]")
            return returnMock(after: 0.2, completion: completion)
        case .live:
            performLiveUpload(image: image, domain: domain, fallbackToMock: false, completion: completion)
        case .autoFallback:
            performLiveUpload(image: image, domain: domain, fallbackToMock: true, completion: completion)
        }
    }

    // 第二次辨認：用相似圖片的 URL 直接再跑一次辨認
    public func analyzeUsingImageURL(_ url: URL,
                                     domain: RecommendationDomain,
                                     completion: @escaping (Result<UploadResponse, Error>) -> Void) {
        debugState = .requesting(endpoint: "/upload [second-pass via image_url]")
        let req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60)
        urlSession.dataTask(with: req) { data, _, error in
            if let error = error {
                DispatchQueue.main.async {
                    self.lastErrorMessage = error.localizedDescription
                    self.debugState = .failure(message: error.localizedDescription, httpStatus: nil, dataSnippet: nil)
                    completion(.failure(error))
                }
                return
            }
            guard let data = data, let img = UIImage(data: data) else {
                let err = NSError(domain: "PictunesService", code: -30, userInfo: [NSLocalizedDescriptionKey: "Cannot load image from \(url.absoluteString)"])
                DispatchQueue.main.async {
                    self.lastErrorMessage = err.localizedDescription
                    self.debugState = .failure(message: err.localizedDescription, httpStatus: nil, dataSnippet: nil)
                    completion(.failure(err))
                }
                return
            }
            // 下載完成後，直接沿用 upload(image:domain:) 流程
            self.upload(image: img, domain: domain, completion: completion)
        }.resume()
    }

    private func performLiveUpload(image: UIImage,
                                   domain: RecommendationDomain,
                                   fallbackToMock: Bool,
                                   completion: @escaping (Result<UploadResponse, Error>) -> Void) {
        lastUsedMock = false
        debugState = .requesting(endpoint: "/upload")

        guard let jpegData = prepareJPEGData(from: image, maxPixel: 1600, quality: 0.75) else {
            let err = NSError(domain: "PictunesService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Cannot convert image to JPEG"])
            lastErrorMessage = err.localizedDescription
            debugState = .failure(message: err.localizedDescription, httpStatus: nil, dataSnippet: nil)
            DispatchQueue.main.async { completion(.failure(err)) }
            return
        }

        var request = URLRequest(url: uploadEndpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"image.jpg\"\r\n")
        body.append("Content-Type: image/jpeg\r\n\r\n")
        body.append(jpegData)
        body.append("\r\n")
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"domain\"\r\n\r\n")
        body.append(backendDomainString(domain))
        body.append("\r\n")
        body.append("--\(boundary)--\r\n")

        urlSession.uploadTask(with: request, from: body) { data, response, error in
            let code = (response as? HTTPURLResponse)?.statusCode
            self.lastHTTPStatus = code

            if let nsErr = error as NSError?, nsErr.domain == NSURLErrorDomain, nsErr.code == NSURLErrorTimedOut {
                self.clog("Upload timed out once. Will downscale more and retry.")
                self.retryAfterTimeout(originalImage: image, domain: domain, fallbackToMock: fallbackToMock, completion: completion)
                return
            }
            if let error = error {
                self.lastErrorMessage = error.localizedDescription
                self.debugState = .failure(message: error.localizedDescription, httpStatus: code, dataSnippet: nil)
                if fallbackToMock { self.switchToMockDueTo(error, completion: completion) }
                else { DispatchQueue.main.async { completion(.failure(error)) } }
                return
            }

            guard let code = code, let data = data, (200..<300).contains(code) else {
                let snippet = data.flatMap { String(data: $0, encoding: .utf8) }?.prefix(200)
                if code == 422 {
                    self.clog("Upload 422, retry-1 with alias fields (TitleCase). Body: \(snippet ?? "")")
                    self.retryUploadWithAlternateFields(jpegData: jpegData,
                                                        domainValue: self.backendDomainString(domain),
                                                        lowercase: false,
                                                        fallbackToMock: fallbackToMock,
                                                        completion: completion)
                    return
                }
                let statusErr = NSError(domain: "PictunesService",
                                        code: code ?? -2,
                                        userInfo: [NSLocalizedDescriptionKey: "Upload failed. HTTP \(code ?? -1). \(snippet ?? "")"])
                self.lastErrorMessage = statusErr.localizedDescription
                self.debugState = .failure(message: statusErr.localizedDescription, httpStatus: code, dataSnippet: data.flatMap { String(data: $0, encoding: .utf8) })
                if fallbackToMock { self.switchToMockDueTo(statusErr, completion: completion) }
                else { DispatchQueue.main.async { completion(.failure(statusErr)) } }
                return
            }

            if let mapped = self.tryDecodeToUploadResponse(data: data) {
                let similarCount = mapped.similar?.count ?? 0
                self.debugState = .success(source: "live", httpStatus: code, detail: "similar=\(similarCount)")
                self.lastErrorMessage = nil
                DispatchQueue.main.async { completion(.success(mapped)) }
                return
            }

            let snippet = String(data: data, encoding: .utf8).flatMap { String($0.prefix(200)) }
            let err = NSError(domain: "PictunesService", code: -10, userInfo: [NSLocalizedDescriptionKey: "Decode failed for /upload. \(snippet ?? "")"])
            self.lastErrorMessage = err.localizedDescription
            self.debugState = .failure(message: err.localizedDescription, httpStatus: code, dataSnippet: snippet)
            if fallbackToMock { self.switchToMockDueTo(err, completion: completion) }
            else { DispatchQueue.main.async { completion(.failure(err)) } }
        }.resume()
    }

    private func retryAfterTimeout(originalImage: UIImage,
                                   domain: RecommendationDomain,
                                   fallbackToMock: Bool,
                                   completion: @escaping (Result<UploadResponse, Error>) -> Void) {
        guard let jpegData = prepareJPEGData(from: originalImage, maxPixel: 1200, quality: 0.6) else {
            let err = NSError(domain: "PictunesService", code: -12, userInfo: [NSLocalizedDescriptionKey: "Cannot downscale image after timeout"])
            DispatchQueue.main.async { completion(.failure(err)) }
            return
        }

        var req = URLRequest(url: uploadEndpoint)
        req.httpMethod = "POST"
        req.timeoutInterval = 120
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let boundary = UUID().uuidString
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"image.jpg\"\r\n")
        body.append("Content-Type: image/jpeg\r\n\r\n")
        body.append(jpegData)
        body.append("\r\n")
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"domain\"\r\n\r\n")
        body.append(backendDomainString(domain))
        body.append("\r\n")
        body.append("--\(boundary)--\r\n")

        urlSession.uploadTask(with: req, from: body) { data, response, error in
            let code = (response as? HTTPURLResponse)?.statusCode
            self.lastHTTPStatus = code

            if let error = error {
                self.lastErrorMessage = error.localizedDescription
                self.debugState = .failure(message: error.localizedDescription, httpStatus: code, dataSnippet: nil)
                if fallbackToMock { self.switchToMockDueTo(error, completion: completion) }
                else { DispatchQueue.main.async { completion(.failure(error)) } }
                return
            }

            guard let code = code, let data = data, (200..<300).contains(code) else {
                let snippet = data.flatMap { String(data: $0, encoding: .utf8) }?.prefix(200)
                if code == 422 {
                    self.clog("Upload retry-after-timeout got 422, will try alias fields.")
                    self.retryUploadWithAlternateFields(jpegData: jpegData,
                                                        domainValue: self.backendDomainString(domain),
                                                        lowercase: false,
                                                        fallbackToMock: fallbackToMock,
                                                        completion: completion)
                    return
                }
                let statusErr = NSError(domain: "PictunesService",
                                        code: code ?? -2,
                                        userInfo: [NSLocalizedDescriptionKey: "Upload failed after timeout retry. HTTP \(code ?? -1). \(snippet ?? "")"])
                self.lastErrorMessage = statusErr.localizedDescription
                self.debugState = .failure(message: statusErr.localizedDescription, httpStatus: code, dataSnippet: data.flatMap { String(data: $0, encoding: .utf8) })
                if fallbackToMock { self.switchToMockDueTo(statusErr, completion: completion) }
                else { DispatchQueue.main.async { completion(.failure(statusErr)) } }
                return
            }

            if let mapped = self.tryDecodeToUploadResponse(data: data) {
                self.debugState = .success(source: "live", httpStatus: code, detail: "success after timeout retry")
                self.lastErrorMessage = nil
                DispatchQueue.main.async { completion(.success(mapped)) }
                return
            }

            let snippet = String(data: data, encoding: .utf8).flatMap { String($0.prefix(200)) }
            let err = NSError(domain: "PictunesService", code: -10, userInfo: [NSLocalizedDescriptionKey: "Decode failed after timeout retry. \(snippet ?? "")"])
            self.lastErrorMessage = err.localizedDescription
            self.debugState = .failure(message: err.localizedDescription, httpStatus: code, dataSnippet: snippet)
            if fallbackToMock { self.switchToMockDueTo(err, completion: completion) }
            else { DispatchQueue.main.async { completion(.failure(err)) } }
        }.resume()
    }

    private func retryUploadWithAlternateFields(jpegData: Data,
                                                domainValue: String,
                                                lowercase: Bool,
                                                fallbackToMock: Bool,
                                                completion: @escaping (Result<UploadResponse, Error>) -> Void) {
        var req = URLRequest(url: uploadEndpoint)
        req.httpMethod = "POST"
        req.timeoutInterval = 120
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let boundary = UUID().uuidString
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let value = lowercase ? domainValue.lowercased() : domainValue

        var body = Data()
        for field in ["file", "image"] {
            body.append("--\(boundary)\r\n")
            body.append("Content-Disposition: form-data; name=\"\(field)\"; filename=\"image.jpg\"\r\n")
            body.append("Content-Type: image/jpeg\r\n\r\n")
            body.append(jpegData)
            body.append("\r\n")
        }
        for field in ["domain", "dataset", "category", "class"] {
            body.append("--\(boundary)\r\n")
            body.append("Content-Disposition: form-data; name=\"\(field)\"\r\n\r\n")
            body.append(value)
            body.append("\r\n")
        }
        body.append("--\(boundary)--\r\n")

        urlSession.uploadTask(with: req, from: body) { data, response, error in
            let code = (response as? HTTPURLResponse)?.statusCode
            self.lastHTTPStatus = code

            if let error = error {
                self.lastErrorMessage = error.localizedDescription
                self.debugState = .failure(message: error.localizedDescription, httpStatus: code, dataSnippet: nil)
                if fallbackToMock { self.switchToMockDueTo(error, completion: completion) }
                else { DispatchQueue.main.async { completion(.failure(error)) } }
                return
            }

            guard let code = code, let data = data, (200..<300).contains(code) else {
                if code == 422 && lowercase == false {
                    let snippet = data.flatMap { String(data: $0, encoding: .utf8) }?.prefix(200)
                    self.clog("Retry-1 still 422, will retry-2 with lowercase. Body: \(snippet ?? "")")
                    self.retryUploadWithAlternateFields(jpegData: jpegData,
                                                        domainValue: value,
                                                        lowercase: true,
                                                        fallbackToMock: fallbackToMock,
                                                        completion: completion)
                    return
                }
                let snippet = data.flatMap { String(data: $0, encoding: .utf8) }?.prefix(200)
                let err = NSError(domain: "PictunesService",
                                  code: code ?? -2,
                                  userInfo: [NSLocalizedDescriptionKey: "Upload retry failed. HTTP \(code ?? -1). \(snippet ?? "")"])
                self.lastErrorMessage = err.localizedDescription
                self.debugState = .failure(message: err.localizedDescription, httpStatus: code, dataSnippet: data.flatMap { String(data: $0, encoding: .utf8) })
                if fallbackToMock { self.switchToMockDueTo(err, completion: completion) }
                else { DispatchQueue.main.async { completion(.failure(err)) } }
                return
            }

            if let mapped = self.tryDecodeToUploadResponse(data: data) {
                let similarCount = mapped.similar?.count ?? 0
                self.debugState = .success(source: "live", httpStatus: code, detail: "retry OK similar=\(similarCount)")
                self.lastErrorMessage = nil
                DispatchQueue.main.async { completion(.success(mapped)) }
            } else {
                let snippet = String(data: data, encoding: .utf8).flatMap { String($0.prefix(200)) }
                let err = NSError(domain: "PictunesService", code: -10, userInfo: [NSLocalizedDescriptionKey: "Decode failed after retry. \(snippet ?? "")"])
                self.lastErrorMessage = err.localizedDescription
                self.debugState = .failure(message: err.localizedDescription, httpStatus: code, dataSnippet: snippet)
                if fallbackToMock { self.switchToMockDueTo(err, completion: completion) }
                else { DispatchQueue.main.async { completion(.failure(err)) } }
            }
        }.resume()
    }

    // MARK: - Media merger（保留你原先的合成功能）

    public func generateVideo(localFile url: URL,
                              completion: @escaping (Result<URL, Error>) -> Void) {
        let exists = FileManager.default.fileExists(atPath: url.path)
        guard exists else {
            let err = NSError(domain: "PictunesService",
                              code: -20,
                              userInfo: [NSLocalizedDescriptionKey: "本機影片不存在：\(url.path)"])
            DispatchQueue.main.async { completion(.failure(err)) }
            return
        }
        DispatchQueue.main.async {
            self.debugState = .success(source: "local", httpStatus: 200, detail: "use local mp4 for preview")
            self.lastErrorMessage = nil
            completion(.success(url))
        }
    }

    public func generateVideoFromBundled(resource name: String,
                                         withExtension ext: String = "mp4",
                                         completion: @escaping (Result<URL, Error>) -> Void) {
        if let url = Bundle.main.url(forResource: name, withExtension: ext) {
            generateVideo(localFile: url, completion: completion)
        } else {
            let err = NSError(domain: "PictunesService",
                              code: -21,
                              userInfo: [NSLocalizedDescriptionKey: "找不到 Bundle 內的 \(name).\(ext)"])
            DispatchQueue.main.async { completion(.failure(err)) }
        }
    }

    public func generateVideo(image: UIImage,
                              audioFileURL: URL,
                              completion: @escaping (Result<URL, Error>) -> Void) {
        switch mode {
        case .mock:
            lastUsedMock = true
            debugState = .requesting(endpoint: "/media_merger [mock]")
            let mockURL = URL(string: "https://filesamples.com/samples/video/mp4/sample_960x400_ocean_with_audio.mp4")!
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.debugState = .success(source: "mock", httpStatus: 200, detail: "Media merged")
                completion(.success(mockURL))
            }
        case .live:
            performMediaMergerUpload(image: image, audioFileURL: audioFileURL, fallbackToMock: false, completion: completion)
        case .autoFallback:
            performMediaMergerUpload(image: image, audioFileURL: audioFileURL, fallbackToMock: true, completion: completion)
        }
    }

    private func performMediaMergerUpload(image: UIImage,
                                          audioFileURL: URL,
                                          fallbackToMock: Bool,
                                          completion: @escaping (Result<URL, Error>) -> Void) {
        lastUsedMock = false
        debugState = .requesting(endpoint: "/media_merger")

        guard let jpegData = prepareJPEGData(from: image, maxPixel: 1600, quality: 0.8) else {
            let err = NSError(domain: "PictunesService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Cannot convert image to JPEG"])
            lastErrorMessage = err.localizedDescription
            debugState = .failure(message: err.localizedDescription, httpStatus: nil, dataSnippet: nil)
            DispatchQueue.main.async { completion(.failure(err)) }
            return
        }

        var audioData: Data
        var stopAccess = false
        if audioFileURL.startAccessingSecurityScopedResource() {
            stopAccess = true
        }
        do {
            audioData = try Data(contentsOf: audioFileURL)
        } catch {
            if stopAccess { audioFileURL.stopAccessingSecurityScopedResource() }
            lastErrorMessage = error.localizedDescription
            debugState = .failure(message: error.localizedDescription, httpStatus: nil, dataSnippet: nil)
            DispatchQueue.main.async { completion(.failure(error)) }
            return
        }
        if stopAccess { audioFileURL.stopAccessingSecurityScopedResource() }

        var request = URLRequest(url: baseURL.appendingPathComponent("media_merger/"))
        request.httpMethod = "POST"
        request.timeoutInterval = 240
        let boundary = "pictunes-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("video/mp4,application/octet-stream,*/*", forHTTPHeaderField: "Accept")

        var body = Data()

        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"img\"; filename=\"image.jpg\"\r\n")
        body.append("Content-Type: image/jpeg\r\n\r\n")
        body.append(jpegData)
        body.append("\r\n")

        let audioFilename = audioFileURL.lastPathComponent.isEmpty ? "audio.\(audioFileURL.pathExtension.isEmpty ? "mp3" : audioFileURL.pathExtension)" : audioFileURL.lastPathComponent
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"aud\"; filename=\"\(audioFilename)\"\r\n")
        body.append("Content-Type: \(mimeTypeForAudio(at: audioFileURL))\r\n\r\n")
        body.append(audioData)
        body.append("\r\n")

        body.append("--\(boundary)--\r\n")

        urlSession.uploadTask(with: request, from: body) { data, response, error in
            let code = (response as? HTTPURLResponse)?.statusCode
            self.lastHTTPStatus = code

            if let error = error {
                self.lastErrorMessage = error.localizedDescription
                if fallbackToMock {
                    let mockURL = URL(string: "https://filesamples.com/samples/video/mp4/sample_960x400_ocean_with_audio.mp4")!
                    self.lastUsedMock = true
                    self.debugState = .failure(message: error.localizedDescription, httpStatus: code, dataSnippet: nil)
                    DispatchQueue.main.async { completion(.success(mockURL)) }
                } else {
                    self.debugState = .failure(message: error.localizedDescription, httpStatus: code, dataSnippet: nil)
                    DispatchQueue.main.async { completion(.failure(error)) }
                }
                return
            }

            guard let code = code, let data = data, (200..<300).contains(code) else {
                let snippet = data.flatMap { String(data: $0, encoding: .utf8) }?.prefix(200)
                let err = NSError(domain: "PictunesService", code: code ?? -2, userInfo: [NSLocalizedDescriptionKey: "media_merger failed. HTTP \(code ?? -1). \(snippet ?? "")"])
                self.lastErrorMessage = err.localizedDescription
                if fallbackToMock {
                    let mockURL = URL(string: "https://filesamples.com/samples/video/mp4/sample_960x400_ocean_with_audio.mp4")!
                    self.lastUsedMock = true
                    self.debugState = .failure(message: err.localizedDescription, httpStatus: code, dataSnippet: data.flatMap { String(data: $0, encoding: .utf8) })
                    DispatchQueue.main.async { completion(.success(mockURL)) }
                } else {
                    self.debugState = .failure(message: err.localizedDescription, httpStatus: code, dataSnippet: data.flatMap { String(data: $0, encoding: .utf8) })
                    DispatchQueue.main.async { completion(.failure(err)) }
                }
                return
            }

            if let mime = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type"),
               mime.lowercased().contains("video/") || !mime.lowercased().contains("json") {
                do {
                    let filename = self.extractFilename(from: (response as? HTTPURLResponse)) ?? "pictunes_\(UUID().uuidString.prefix(8)).mp4"
                    let tmpURL = try self.saveVideoToTemporaryFile(data: data, preferredFilename: filename)
                    self.debugState = .success(source: "live", httpStatus: code, detail: "binary video")
                    self.lastErrorMessage = nil
                    DispatchQueue.main.async { completion(.success(tmpURL)) }
                    return
                } catch {
                    self.lastErrorMessage = error.localizedDescription
                    if fallbackToMock {
                        let mockURL = URL(string: "https://filesamples.com/samples/video/mp4/sample_960x400_ocean_with_audio.mp4")!
                        self.lastUsedMock = true
                        self.debugState = .failure(message: error.localizedDescription, httpStatus: code, dataSnippet: nil)
                        DispatchQueue.main.async { completion(.success(mockURL)) }
                    } else {
                        self.debugState = .failure(message: error.localizedDescription, httpStatus: code, dataSnippet: nil)
                        DispatchQueue.main.async { completion(.failure(error)) }
                    }
                    return
                }
            }

            struct RenderRespA: Codable { let video_url: URL? }
            struct RenderRespB: Codable { let videoUrl: URL? }
            if let respA = try? JSONDecoder().decode(RenderRespA.self, from: data), let u = respA.video_url {
                let abs = self.absolutize(u) ?? u
                self.debugState = .success(source: "live", httpStatus: code, detail: "video_url JSON")
                self.lastErrorMessage = nil
                DispatchQueue.main.async { completion(.success(abs)) }
                return
            }
            if let respB = try? JSONDecoder().decode(RenderRespB.self, from: data), let u = respB.videoUrl {
                let abs = self.absolutize(u) ?? u
                self.debugState = .success(source: "live", httpStatus: code, detail: "videoUrl JSON")
                self.lastErrorMessage = nil
                DispatchQueue.main.async { completion(.success(abs)) }
                return
            }

            let err = NSError(domain: "PictunesService", code: -11, userInfo: [NSLocalizedDescriptionKey: "Unknown media_merger response"])
            self.lastErrorMessage = err.localizedDescription
            self.debugState = .failure(message: err.localizedDescription, httpStatus: code, dataSnippet: nil)
            DispatchQueue.main.async { completion(.failure(err)) }
        }.resume()
    }
    
    // MARK: - Media merger: 圖片 + 遠端音檔 URL

    public func generateVideoUsingRemoteAudioURL(
        image: UIImage,
        audioURL: URL,
        start: Int? = nil,
        end: Int? = nil,
        domain: RecommendationDomain? = nil,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        lastUsedMock = false
        debugState = .requesting(endpoint: "/media_merger")

        guard let jpegData = prepareJPEGData(from: image, maxPixel: 1600, quality: 0.8) else {
            let err = NSError(domain: "PictunesService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Cannot convert image to JPEG"])
            lastErrorMessage = err.localizedDescription
            debugState = .failure(message: err.localizedDescription, httpStatus: nil, dataSnippet: nil)
            DispatchQueue.main.async { completion(.failure(err)) }
            return
        }

        var request = URLRequest(url: baseURL.appendingPathComponent("media_merger/"))
        request.httpMethod = "POST"
        request.timeoutInterval = 240
        let boundary = "pictunes-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("video/mp4,application/octet-stream,*/*", forHTTPHeaderField: "Accept")

        var body = Data()

        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"img\"; filename=\"image.jpg\"\r\n")
        body.append("Content-Type: image/jpeg\r\n\r\n")
        body.append(jpegData)
        body.append("\r\n")

        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"audio_url\"\r\n\r\n")
        body.append(audioURL.absoluteString)
        body.append("\r\n")

        if let s = start {
            body.append("--\(boundary)\r\n")
            body.append("Content-Disposition: form-data; name=\"start\"\r\n\r\n")
            body.append(String(s))
            body.append("\r\n")
        }
        if let e = end {
            body.append("--\(boundary)\r\n")
            body.append("Content-Disposition: form-data; name=\"end\"\r\n\r\n")
            body.append(String(e))
            body.append("\r\n")
        }
        if let d = domain {
            body.append("--\(boundary)\r\n")
            body.append("Content-Disposition: form-data; name=\"domain\"\r\n\r\n")
            body.append(backendDomainString(d))
            body.append("\r\n")
        }

        body.append("--\(boundary)--\r\n")

        urlSession.uploadTask(with: request, from: body) { data, response, error in
            let code = (response as? HTTPURLResponse)?.statusCode
            self.lastHTTPStatus = code

            if let error = error {
                self.lastErrorMessage = error.localizedDescription
                self.debugState = .failure(message: error.localizedDescription, httpStatus: code, dataSnippet: nil)
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }

            guard let code = code, let data = data, (200..<300).contains(code) else {
                let snippet = data.flatMap { String(data: $0, encoding: .utf8) }?.prefix(200)
                let err = NSError(domain: "PictunesService", code: code ?? -2, userInfo: [NSLocalizedDescriptionKey: "media_merger failed. HTTP \(code ?? -1). \(snippet ?? "")"])
                self.lastErrorMessage = err.localizedDescription
                self.debugState = .failure(message: err.localizedDescription, httpStatus: code, dataSnippet: data.flatMap { String(data: $0, encoding: .utf8) })
                DispatchQueue.main.async { completion(.failure(err)) }
                return
            }

            if let mime = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type"),
               mime.lowercased().contains("video/") || !mime.lowercased().contains("json") {
                do {
                    let filename = self.extractFilename(from: (response as? HTTPURLResponse)) ?? "pictunes_\(UUID().uuidString.prefix(8)).mp4"
                    let tmpURL = try self.saveVideoToTemporaryFile(data: data, preferredFilename: filename)
                    self.debugState = .success(source: "live", httpStatus: code, detail: "binary video")
                    self.lastErrorMessage = nil
                    DispatchQueue.main.async { completion(.success(tmpURL)) }
                    return
                } catch {
                    self.lastErrorMessage = error.localizedDescription
                    self.debugState = .failure(message: error.localizedDescription, httpStatus: code, dataSnippet: nil)
                    DispatchQueue.main.async { completion(.failure(error)) }
                    return
                }
            }

            struct RespA: Codable { let video_url: URL? }
            struct RespB: Codable { let videoUrl: URL? }
            if let r = try? JSONDecoder().decode(RespA.self, from: data), let u = r.video_url {
                let abs = self.absolutize(u) ?? u
                self.debugState = .success(source: "live", httpStatus: code, detail: "video_url JSON")
                DispatchQueue.main.async { completion(.success(abs)) }
                return
            }
            if let r = try? JSONDecoder().decode(RespB.self, from: data), let u = r.videoUrl {
                let abs = self.absolutize(u) ?? u
                self.debugState = .success(source: "live", httpStatus: code, detail: "videoUrl JSON")
                DispatchQueue.main.async { completion(.success(abs)) }
                return
            }

            let err = NSError(domain: "PictunesService", code: -11, userInfo: [NSLocalizedDescriptionKey: "Unknown media_merger response"])
            self.lastErrorMessage = err.localizedDescription
            self.debugState = .failure(message: err.localizedDescription, httpStatus: code, dataSnippet: nil)
            DispatchQueue.main.async { completion(.failure(err)) }
        }.resume()
    }
    
    // 以 music_id 進行合成：優先嘗試 /media_merger_id/，失敗後回退 /media_merger/ 並帶 music_id
    public func generateVideoUsingMusicID(
        image: UIImage,
        musicID: Int,
        start: Int? = nil,
        end: Int? = nil,
        domain: RecommendationDomain? = nil,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        lastUsedMock = false
        debugState = .requesting(endpoint: "/media_merger_id -> /media_merger fallback")

        guard let jpegData = prepareJPEGData(from: image, maxPixel: 1600, quality: 0.8) else {
            let err = NSError(domain: "PictunesService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Cannot convert image to JPEG"])
            lastErrorMessage = err.localizedDescription
            debugState = .failure(message: err.localizedDescription, httpStatus: nil, dataSnippet: nil)
            DispatchQueue.main.async { completion(.failure(err)) }
            return
        }

        func makeMultipartBody(boundary: String, extraFields: [(name: String, value: String)]) -> Data {
            var body = Data()

            body.append("--\(boundary)\r\n")
            body.append("Content-Disposition: form-data; name=\"img\"; filename=\"image.jpg\"\r\n")
            body.append("Content-Type: image/jpeg\r\n\r\n")
            body.append(jpegData)
            body.append("\r\n")

            for (name, value) in extraFields {
                body.append("--\(boundary)\r\n")
                body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
                body.append(value)
                body.append("\r\n")
            }

            if let s = start {
                body.append("--\(boundary)\r\n")
                body.append("Content-Disposition: form-data; name=\"start\"\r\n\r\n")
                body.append(String(s))
                body.append("\r\n")
            }
            if let e = end {
                body.append("--\(boundary)\r\n")
                body.append("Content-Disposition: form-data; name=\"end\"\r\n\r\n")
                body.append(String(e))
                body.append("\r\n")
            }
            if let d = domain {
                body.append("--\(boundary)\r\n")
                body.append("Content-Disposition: form-data; name=\"domain\"\r\n\r\n")
                body.append(self.backendDomainString(d))
                body.append("\r\n")
            }

            body.append("--\(boundary)--\r\n")
            return body
        }

        func handleSuccess(data: Data, response: URLResponse?, completion: @escaping (Result<URL, Error>) -> Void) {
            let code = (response as? HTTPURLResponse)?.statusCode
            if let mime = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type"),
               mime.lowercased().contains("video/") || !mime.lowercased().contains("json") {
                do {
                    let filename = self.extractFilename(from: (response as? HTTPURLResponse)) ?? "pictunes_\(UUID().uuidString.prefix(8)).mp4"
                    let tmpURL = try self.saveVideoToTemporaryFile(data: data, preferredFilename: filename)
                    self.debugState = .success(source: "live", httpStatus: code, detail: "binary video")
                    self.lastErrorMessage = nil
                    DispatchQueue.main.async { completion(.success(tmpURL)) }
                    return
                } catch {
                    self.lastErrorMessage = error.localizedDescription
                    self.debugState = .failure(message: error.localizedDescription, httpStatus: code, dataSnippet: nil)
                    DispatchQueue.main.async { completion(.failure(error)) }
                    return
                }
            }

            struct RespA: Codable { let video_url: URL? }
            struct RespB: Codable { let videoUrl: URL? }
            if let r = try? JSONDecoder().decode(RespA.self, from: data), let u = r.video_url {
                let abs = self.absolutize(u) ?? u
                self.debugState = .success(source: "live", httpStatus: code, detail: "video_url JSON")
                DispatchQueue.main.async { completion(.success(abs)) }
                return
            }
            if let r = try? JSONDecoder().decode(RespB.self, from: data), let u = r.videoUrl {
                let abs = self.absolutize(u) ?? u
                self.debugState = .success(source: "live", httpStatus: code, detail: "videoUrl JSON")
                DispatchQueue.main.async { completion(.success(abs)) }
                return
            }

            let err = NSError(domain: "PictunesService", code: -11, userInfo: [NSLocalizedDescriptionKey: "Unknown media_merger response"])
            self.lastErrorMessage = err.localizedDescription
            self.debugState = .failure(message: err.localizedDescription, httpStatus: code, dataSnippet: nil)
            DispatchQueue.main.async { completion(.failure(err)) }
        }

        func tryIDEndpoint() {
            var request = URLRequest(url: baseURL.appendingPathComponent("media_merger_id/"))
            request.httpMethod = "POST"
            request.timeoutInterval = 240
            let boundary = "pictunes-\(UUID().uuidString)"
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            request.setValue("video/mp4,application/json,*/*", forHTTPHeaderField: "Accept")

            let body = makeMultipartBody(boundary: boundary, extraFields: [
                ("music_id", String(musicID)),
                ("musicId", String(musicID))      // 別名，增加相容性
            ])

            urlSession.uploadTask(with: request, from: body) { data, response, error in
                let code = (response as? HTTPURLResponse)?.statusCode
                self.lastHTTPStatus = code

                if let error = error {
                    tryFallbackEndpoint(reason: error.localizedDescription)
                    return
                }
                guard let code = code, let data = data else {
                    tryFallbackEndpoint(reason: "No response")
                    return
                }
                if code == 404 {
                    tryFallbackEndpoint(reason: "404 media_merger_id not found")
                    return
                }
                if (200..<300).contains(code) {
                    handleSuccess(data: data, response: response, completion: completion)
                    return
                }
                tryFallbackEndpoint(reason: "HTTP \(code)")
            }.resume()
        }

        func tryFallbackEndpoint(reason: String) {
            var request = URLRequest(url: baseURL.appendingPathComponent("media_merger/"))
            request.httpMethod = "POST"
            request.timeoutInterval = 240
            let boundary = "pictunes-\(UUID().uuidString)"
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            request.setValue("video/mp4,application/json,*/*", forHTTPHeaderField: "Accept")

            let body = makeMultipartBody(boundary: boundary, extraFields: [
                ("music_id", String(musicID)),
                ("musicId", String(musicID)),
                ("id", String(musicID))
            ])

            urlSession.uploadTask(with: request, from: body) { data, response, error in
                let code = (response as? HTTPURLResponse)?.statusCode
                self.lastHTTPStatus = code

                if let error = error {
                    self.lastErrorMessage = error.localizedDescription
                    self.debugState = .failure(message: "media_merger fallback failed: \(reason) -> \(error.localizedDescription)", httpStatus: code, dataSnippet: nil)
                    DispatchQueue.main.async { completion(.failure(error)) }
                    return
                }

                guard let code = code, let data = data else {
                    let err = NSError(domain: "PictunesService", code: -2, userInfo: [NSLocalizedDescriptionKey: "media_merger fallback: empty response"])
                    self.lastErrorMessage = err.localizedDescription
                    self.debugState = .failure(message: err.localizedDescription, httpStatus: nil, dataSnippet: nil)
                    DispatchQueue.main.async { completion(.failure(err)) }
                    return
                }

                if (200..<300).contains(code) {
                    handleSuccess(data: data, response: response, completion: completion)
                    return
                }

                let snippet = String(data: data, encoding: .utf8)
                let err = NSError(domain: "PictunesService", code: code, userInfo: [NSLocalizedDescriptionKey: "media_merger failed. HTTP \(code). \(snippet ?? "")"])
                self.lastErrorMessage = err.localizedDescription
                self.debugState = .failure(message: err.localizedDescription, httpStatus: code, dataSnippet: snippet)
                DispatchQueue.main.async { completion(.failure(err)) }
            }.resume()
        }

        tryIDEndpoint()
    }


    // MARK: - Parsing helpers（含 music_match 與 80% 門檻）

    private func tryDecodeToUploadResponse(data: Data) -> UploadResponse? {
        if logRawUploadResponse, let s = String(data: data, encoding: .utf8) {
            print("[Pictunes] RAW upload JSON:", s.prefix(1200))
        }

        if let decoded = try? JSONDecoder().decode(UploadResponse.self, from: data) {
            return normalizeURLs(in: decoded)
        }

        if let mapped = mapMatchesWithMusicIfPossible(data) {
            return normalizeURLs(in: mapped)
        }

        struct Match: Codable { let similarity: Double?; let filename: String?; let `class`: String?; let full_path: String?; let image_url: String? }
        struct MatchesPayload: Codable { let status: String?; let matches: [Match]? }
        if let m = try? JSONDecoder().decode(MatchesPayload.self, from: data), let list = m.matches, !list.isEmpty {
            let items = list.map { x -> SimilarItem in
                let lbl = x.class ?? "unknown"
                let urlStr = x.image_url ?? x.full_path ?? "https://picsum.photos/seed/\(x.filename ?? "img")/600/400"
                let url = absolutizeString(urlStr) ?? URL(string: "https://picsum.photos/seed/\(x.filename ?? "img")/600/400")!
                return SimilarItem(imageUrl: url, score: x.similarity ?? 0, label: lbl, style: nil, filename: x.filename)
            }
            return normalizeURLs(in: UploadResponse(label: m.status ?? "success", music: [], similar: items, videoUrl: nil))
        }

        if let root = try? JSONSerialization.jsonObject(with: data) {
            if let arrRoot = root as? [[String:Any]], !arrRoot.isEmpty {
                let items = mapGenericList(arrRoot)
                return normalizeURLs(in: UploadResponse(label: "success", music: [], similar: items, videoUrl: nil))
            }

            if let dictRoot = root as? [String:Any] {
                if let arr = deepFirstArray(in: dictRoot), !arr.isEmpty {
                    let items = mapGenericList(arr)
                    let label = (dictRoot["label"] as? String)
                              ?? (dictRoot["status"] as? String)
                              ?? (dictRoot["message"] as? String)
                              ?? "success"
                    return normalizeURLs(in: UploadResponse(label: label, music: [], similar: items, videoUrl: nil))
                }
            }
        }

        return nil
    }

    private func mapMatchesWithMusicIfPossible(_ data: Data) -> UploadResponse? {
        struct MusicMatch: Codable {
            let music_id: Int?
            let music_name: String?
            let anime_title: String?
            let piece: String?
            let duration: String?
            let youtube_link: String?
            let composer: String?
            let kind: String?
        }
        struct MatchX: Codable {
            let similarity: Double?
            let filename: String?
            let `class`: String?
            let full_path: String?
            let image_url: String?
            let music_match: MusicMatch?
        }
        struct Root: Codable {
            let status: String?
            let matches: [MatchX]?
        }

        guard let r = try? JSONDecoder().decode(Root.self, from: data),
              let list = r.matches, !list.isEmpty else { return nil }

        var items: [SimilarItem] = []
        var musics: [Music] = []

        for x in list {
            let score = x.similarity ?? 0
            let lbl = x.class ?? "unknown"
            let urlStr = x.image_url ?? x.full_path ?? "https://picsum.photos/seed/\(x.filename ?? "img")/600/400"
            let url = absolutizeString(urlStr) ?? URL(string: "https://picsum.photos/seed/\(x.filename ?? "img")/600/400")!
            items.append(SimilarItem(imageUrl: url, score: score, label: lbl, style: nil, filename: x.filename))

            if score >= 0.8, let m = x.music_match {
                let (s, e) = parseDurationRange(m.duration) ?? (0, 20)
                let title = (m.music_name ?? "").isEmpty ? (m.anime_title ?? "Unknown") : m.music_name!
                let composer = m.composer ?? (m.anime_title ?? "Unknown")
                let link = m.youtube_link ?? ""
                let mid = m.music_id
                musics.append(Music(title: title, composer: composer, start: s, end: e, link: link, backendMusicID: mid))
            }
        }

        return UploadResponse(label: r.status ?? "success", music: musics, similar: items, videoUrl: nil)
    }

    private func normalizeURLs(in response: UploadResponse) -> UploadResponse {
        let fixedVideo = absolutize(response.videoUrl)
        let fixedSimilar: [SimilarItem]? = response.similar?.map { item in
            let fixed = absolutize(item.imageUrl) ?? item.imageUrl
            return SimilarItem(imageUrl: fixed, score: item.score, label: item.label, style: item.style, filename: item.filename)
        }
        return UploadResponse(label: response.label, music: response.music, similar: fixedSimilar, videoUrl: fixedVideo)
    }

    private func absolutize(_ url: URL?) -> URL? {
        guard let u = url else { return nil }
        if u.scheme == nil {
            let path = u.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return baseURL.appendingPathComponent(path)
        }
        return u
    }

    private func absolutizeString(_ s: String) -> URL? {
        if let u = URL(string: s), u.scheme != nil { return u }
        let norm = normalizedRelativeDatasetPath(s)
        let withRoot = norm.hasPrefix("/") ? String(norm.dropFirst()) : norm
        let primary = baseURL.appendingPathComponent(withRoot)
        return primary
    }

    private func normalizedRelativeDatasetPath(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("./") { s.removeFirst(2) }
        while s.hasPrefix("/") { s.removeFirst() }

        if s.lowercased().hasPrefix("image/") { return "/\(s)" }
        if s.lowercased().hasPrefix("static/") { return "/\(s)" }
        if s.lowercased().hasPrefix("dataset/") {
            let root = publicImageRootPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return "/\(root)/\(s.dropFirst("dataset/".count))"
        }
        let root = publicImageRootPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return "/\(root)/\(s)"
    }

    private func deepFirstArray(in dict: [String:Any]) -> [[String:Any]]? {
        let candidateKeys = [
            "images", "matches",
            "top_10_matches", "top10", "top", "top_matches",
            "all_top_matches", "all_class_matches",
            "items", "results", "list"
        ]
        for k in candidateKeys {
            if let arr = dict[k] as? [[String:Any]], !arr.isEmpty { return arr }
            if let anyArr = dict[k] as? [Any], let arr = anyArr as? [[String:Any]], !arr.isEmpty { return arr }
        }
        for (_, v) in dict {
            if let sub = v as? [String:Any], let found = deepFirstArray(in: sub) { return found }
            if let arrDict = v as? [[String:Any]], !arrDict.isEmpty { return arrDict }
            if let arr = v as? [Any] {
                for e in arr {
                    if let d = e as? [String:Any], let found = deepFirstArray(in: d) { return found }
                }
            }
        }
        return nil
    }

    private func mapGenericList(_ arr: [[String: Any]]) -> [SimilarItem] {
        func str(_ d: [String:Any], _ keys: [String]) -> String? {
            for k in keys {
                if let v = d[k] as? String, !v.isEmpty { return v }
                if let n = d[k] as? NSNumber { return n.stringValue }
            }
            return nil
        }
        func dbl(_ d: [String:Any], _ keys: [String]) -> Double? {
            for k in keys {
                if let v = d[k] as? Double { return v }
                if let v = d[k] as? Float { return Double(v) }
                if let v = d[k] as? Int { return Double(v) }
                if let s = d[k] as? String, let v = Double(s) { return v }
            }
            return nil
        }
        func ensureJpg(_ name: String) -> String {
            let lower = name.lowercased()
            if lower.hasSuffix(".jpg") || lower.hasSuffix(".jpeg") || lower.hasSuffix(".png") { return name }
            return name + ".jpg"
        }

        return arr.compactMap { d in
            let urlStr  = str(d, ["image_url","imageUrl","full_path","url","path","imagePath"])
            let label   = str(d, ["label","class","title","name"])
            let style   = str(d, ["style"])
            var file    = str(d, ["filename","file","id"])
            let score   = dbl(d, ["score","similarity","sim","prob"]) ?? 0

            if let s = urlStr, let abs = absolutizeString(s) {
                if file == nil { file = abs.lastPathComponent }
                return SimilarItem(imageUrl: abs, score: score, label: label, style: style, filename: file)
            }

            if let filename = file ?? str(d, ["id"]),
               let cls = label {
                let sanitizedClass = cls.replacingOccurrences(of: " ", with: "_")
                let relative = "dataset/\(sanitizedClass)/\(ensureJpg(filename))"
                if let abs = absolutizeString(relative) {
                    return SimilarItem(imageUrl: abs, score: score, label: label, style: style, filename: filename)
                }
            }

            let seed = file ?? label ?? "img"
            let fallback = URL(string: "https://picsum.photos/seed/\(seed)/600/400")!
            return SimilarItem(imageUrl: fallback, score: score, label: label, style: style, filename: file)
        }
    }

    // 共用小工具
    private func backendDomainString(_ domain: RecommendationDomain) -> String {
        switch domain { case .anime: return "Anime"; case .film: return "Film" }
    }

    private func prepareJPEGData(from image: UIImage, maxPixel: CGFloat, quality: CGFloat) -> Data? {
        let size = image.size
        let maxSide = max(size.width, size.height)
        let scale = max(1, maxSide / maxPixel)
        let target = CGSize(width: size.width / scale, height: size.height / scale)

        UIGraphicsBeginImageContextWithOptions(target, true, 1.0)
        image.draw(in: CGRect(origin: .zero, size: target))
        let resized = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        guard let img = resized, var data = img.jpegData(compressionQuality: quality) else { return nil }
        if data.count > 4_000_000, let d2 = img.jpegData(compressionQuality: 0.6) {
            data = d2
        }
        return data
    }

    private func parseDurationRange(_ raw: String?) -> (Int, Int)? {
        guard var s = raw else { return nil }
        s = s.replacingOccurrences(of: "\n", with: "").replacingOccurrences(of: " ", with: "")
        let parts = s.split(separator: "-").map { String($0) }
        guard parts.count == 2 else { return nil }
        func toSec(_ t: String) -> Int? {
            let comps = t.split(separator: ":").map { String($0) }
            guard comps.count == 2, let m = Int(comps[0]), let sec = Int(comps[1]) else { return nil }
            return m*60 + sec
        }
        if let a = toSec(parts[0]), let b = toSec(parts[1]) {
            return (min(a,b), max(a,b))
        }
        return nil
    }

    private func clog(_ message: String) {
        print("[Pictunes] \(message)")
        logger.info("\(message, privacy: .public)")
    }
    
    // 從回應標頭解析檔名（支援 filename 與 RFC 5987 的 filename*）
    private func extractFilename(from response: HTTPURLResponse?) -> String? {
        guard let header = response?.value(forHTTPHeaderField: "Content-Disposition") else {
            return nil
        }

        // 先抓 RFC 5987 標準寫法：filename*=UTF-8''xxx.mp4
        if let range = header.range(of: "filename*=") {
            let sub = header[range.upperBound...]
            // 形如 UTF-8''abc%20def.mp4
            if let twoQuotes = sub.firstIndex(of: "'"),
               let threeQuotes = sub[sub.index(after: twoQuotes)...].firstIndex(of: "'") {
                let encoded = sub[sub.index(after: threeQuotes)...].trimmingCharacters(in: .whitespacesAndNewlines)
                let cleaned = encoded.trimmingCharacters(in: CharacterSet(charactersIn: "\"; "))
                return cleaned.removingPercentEncoding
            }
        }

        // 傳統寫法：filename="xxx.mp4" 或 filename=xxx.mp4
        if let r = header.range(of: "filename=") {
            let sub = header[r.upperBound...]
            var cand = sub.trimmingCharacters(in: .whitespacesAndNewlines)
            if cand.hasPrefix("\""), let q = cand.dropFirst().firstIndex(of: "\"") {
                cand = String(cand[cand.index(after: cand.startIndex)..<q])
            } else if let semi = cand.firstIndex(of: ";") {
                cand = String(cand[..<semi])
            }
            cand = cand.trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
            if !cand.isEmpty { return cand }
        }

        return nil
    }

    // 將後端回傳的二進位影片資料存到暫存路徑，回傳本機檔案 URL
    private func saveVideoToTemporaryFile(data: Data, preferredFilename: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
        let safeName: String = {
            let name = preferredFilename.isEmpty ? "pictunes_\(UUID().uuidString.prefix(8)).mp4" : preferredFilename
            if (name as NSString).pathExtension.isEmpty { return name + ".mp4" }
            return name
        }()
        let url = dir.appendingPathComponent(safeName)
        try? FileManager.default.removeItem(at: url)
        try data.write(to: url, options: [.atomic])
        return url
    }
    // 根據副檔名推斷音訊 MIME；優先用 UniformTypeIdentifiers，沒有就用對照表
    private func mimeTypeForAudio(at url: URL) -> String {
        let ext = url.pathExtension.lowercased()

        if !ext.isEmpty, let type = UTType(filenameExtension: ext), let mime = type.preferredMIMEType {
            return mime
        }

        switch ext {
        case "mp3":  return "audio/mpeg"
        case "m4a":  return "audio/mp4"
        case "aac":  return "audio/aac"
        case "wav":  return "audio/wav"
        case "flac": return "audio/flac"
        case "ogg":  return "audio/ogg"
        case "oga":  return "audio/ogg"
        case "opus": return "audio/ogg"
        case "caf":  return "audio/x-caf"
        default:     return "application/octet-stream"
        }
    }



    // MARK: - Mock helpers

    private func switchToMockDueTo(_ error: Error, completion: @escaping (Result<UploadResponse, Error>) -> Void) {
        lastUsedMock = true
        returnMock(after: 0.2, completion: completion)
    }

    private func returnMock(after delay: TimeInterval,
                            completion: @escaping (Result<UploadResponse, Error>) -> Void) {
        let mock = UploadResponse(
            label: "beach sunset",
            music: [
                Music(title: "Clair de Lune", composer: "Debussy", start: 30, end: 60, link: "https://www.youtube.com/watch?v=CvFH_6DNRCY", backendMusicID: nil),
                Music(title: "Gymnopédie No.1", composer: "Erik Satie", start: 10, end: 45, link: "https://www.youtube.com/watch?v=S-Xm7s9eGxU", backendMusicID: nil)
            ],
            similar: [
                SimilarItem(imageUrl: URL(string: "https://picsum.photos/seed/sim1/600/400")!, score: 0.873, label: "sunset", style: "warm", filename: "sim1"),
                SimilarItem(imageUrl: URL(string: "https://picsum.photos/seed/sim2/600/400")!, score: 0.842, label: "beach", style: "calm", filename: "sim2"),
                SimilarItem(imageUrl: URL(string: "https://picsum.photos/seed/sim3/600/400")!, score: 0.801, label: "sky", style: "bright", filename: "sim3")
            ],
            videoUrl: URL(string: "https://filesamples.com/samples/video/mp4/sample_960x400_ocean_with_audio.mp4")
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            self.debugState = .success(source: "mock", httpStatus: 200, detail: "mock upload")
            self.lastErrorMessage = nil
            completion(.success(mock))
        }
    }
}

// MARK: - Data helpers

private extension Data {
    mutating func append(_ string: String) {
        if let d = string.data(using: .utf8) { append(d) }
    }
}

// MARK: - Int formatting

public extension Int {
    var timeFormatted: String {
        let total = Swift.max(0, self)
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
