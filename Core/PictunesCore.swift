// PictunesCore.swift
import Foundation
import UIKit
import Combine
import os

// MARK: - Models

public struct Music: Identifiable, Codable, Equatable {
    public var id = UUID()
    public let title: String
    public let composer: String
    public let start: Int
    public let end: Int
    public let link: String

    private enum CodingKeys: String, CodingKey {
        case title, composer, start, end, link
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
    public var logRawUploadResponse: Bool = false   // 打開後會列印原始 JSON 片段，方便對照
    
    public var publicImageRootPath: String = "/image"
    // 保留一個備援，若未來仍有舊機制會回 /dataset
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

    // Base URL：優先讀 Info.plist 的 PictunesAPIBaseURL，否則用預設
    private static let defaultBaseURL = "https://api.pictunes.me"
    private var baseURL: URL = {
        if let raw = Bundle.main.object(forInfoDictionaryKey: "PictunesAPIBaseURL") as? String,
           let url = URL(string: raw) {
            return url
        }
        return URL(string: defaultBaseURL)!
    }()

    // Endpoints（不帶尾斜線）
    private var uploadEndpoint: URL { baseURL.appendingPathComponent("upload") }
    private var mediaMergerEndpoint: URL { baseURL.appendingPathComponent("media_merger") }
    private var healthEndpoint: URL { baseURL.appendingPathComponent("health") }
    private var dbconCheckEndpoint: URL { baseURL.appendingPathComponent("dbcon_check") }

    // URLSession：放寬逾時
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

    // MARK: - Upload API

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

    // MARK: - Media merger（公開）

    public func generateVideo(image: UIImage,
                              domain: RecommendationDomain,
                              track: Music,
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
            performLiveMediaMerger(image: image, domain: domain, track: track, fallbackToMock: false, completion: completion)
        case .autoFallback:
            performLiveMediaMerger(image: image, domain: domain, track: track, fallbackToMock: true, completion: completion)
        }
    }

    // MARK: - Internal helpers

    private func backendDomainString(_ domain: RecommendationDomain) -> String {
        switch domain { case .anime: return "Anime"; case .film: return "Film" }
    }
    private func backendDomainLower(_ domain: RecommendationDomain) -> String {
        switch domain { case .anime: return "anime"; case .film: return "film" }
    }

    // 影像上傳：先縮圖、再上傳；422 會做兩段重試；-1001 會縮更小再重送一次
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

    // 422 的欄位別名重試；lowercase=false 送 Anime/Film；true 送 anime/film
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

    // Media merger：沿用新的逾時與縮圖策略
    private func performLiveMediaMerger(image: UIImage,
                                        domain: RecommendationDomain,
                                        track: Music,
                                        fallbackToMock: Bool,
                                        completion: @escaping (Result<URL, Error>) -> Void) {
        lastUsedMock = false
        debugState = .requesting(endpoint: "/media_merger")

        guard let jpegData = prepareJPEGData(from: image, maxPixel: 1600, quality: 0.75) else {
            let err = NSError(domain: "PictunesService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Cannot convert image to JPEG"])
            lastErrorMessage = err.localizedDescription
            debugState = .failure(message: err.localizedDescription, httpStatus: nil, dataSnippet: nil)
            DispatchQueue.main.async { completion(.failure(err)) }
            return
        }

        var req = URLRequest(url: mediaMergerEndpoint)
        req.httpMethod = "POST"
        req.timeoutInterval = 120
        let boundary = UUID().uuidString
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"image.jpg\"\r\n")
        body.append("Content-Type: image/jpeg\r\n\r\n")
        body.append(jpegData)
        body.append("\r\n")
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"audio_url\"\r\n\r\n")
        body.append(track.link)
        body.append("\r\n")
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"start\"\r\n\r\n")
        body.append(String(track.start))
        body.append("\r\n")
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"end\"\r\n\r\n")
        body.append(String(track.end))
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
                let err = NSError(domain: "PictunesService", code: code ?? -3, userInfo: [NSLocalizedDescriptionKey: "Media merger failed. HTTP \(code ?? -1). \(snippet ?? "")"])
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

            if let mime = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type"),
               mime.lowercased().contains("video/") || !mime.lowercased().contains("json") {
                do {
                    let tmpURL = try self.saveVideoToTemporaryFile(data: data)
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

            let err = NSError(domain: "PictunesService", code: -11, userInfo: [NSLocalizedDescriptionKey: "Unknown media_merger response"])
            self.lastErrorMessage = err.localizedDescription
            if fallbackToMock {
                let mockURL = URL(string: "https://filesamples.com/samples/video/mp4/sample_960x400_ocean_with_audio.mp4")!
                self.lastUsedMock = true
                self.debugState = .failure(message: err.localizedDescription, httpStatus: code, dataSnippet: nil)
                DispatchQueue.main.async { completion(.success(mockURL)) }
            } else {
                self.debugState = .failure(message: err.localizedDescription, httpStatus: code, dataSnippet: nil)
                DispatchQueue.main.async { completion(.failure(err)) }
            }
        }.resume()
    }

    // 解析多種回傳為 UploadResponse；會遞迴搜尋 data/result/payload 內層，
    // 並且支援 top_10_matches / all_top_matches / all_class_matches
    private func tryDecodeToUploadResponse(data: Data) -> UploadResponse? {
        if logRawUploadResponse, let s = String(data: data, encoding: .utf8) {
            print("[Pictunes] RAW upload JSON:", s.prefix(800))
        }

        // 1) 直接是我們的模型
        if let decoded = try? JSONDecoder().decode(UploadResponse.self, from: data) {
            return normalizeURLs(in: decoded)
        }

        // 2) 舊格式：{ status, matches: [...] }
        struct Match: Codable { let similarity: Double?; let filename: String?; let `class`: String?; let full_path: String? }
        struct MatchesPayload: Codable { let status: String?; let matches: [Match]? }
        if let m = try? JSONDecoder().decode(MatchesPayload.self, from: data), let list = m.matches, !list.isEmpty {
            let items = list.map { x -> SimilarItem in
                let lbl = x.class ?? "unknown"
                let urlStr = x.full_path ?? "https://picsum.photos/seed/\(x.filename ?? "img")/600/400"
                let url = absolutizeString(urlStr) ?? URL(string: "https://picsum.photos/seed/\(x.filename ?? "img")/600/400")!
                return SimilarItem(imageUrl: url, score: x.similarity ?? 0, label: lbl, style: nil, filename: x.filename)
            }
            return normalizeURLs(in: UploadResponse(label: m.status ?? "success", music: [], similar: items, videoUrl: nil))
        }

        // 3) 動態解析：尋找清單鍵（含 top_10_matches / all_top_matches / all_class_matches）
        if let root = try? JSONSerialization.jsonObject(with: data) {

            // 3a) 回傳是 array 直接 map
            if let arrRoot = root as? [[String:Any]], !arrRoot.isEmpty {
                let items = mapGenericList(arrRoot)
                return normalizeURLs(in: UploadResponse(label: "success", music: [], similar: items, videoUrl: nil))
            }

            // 3b) 回傳是 dict：遞迴找第一個非空清單
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

    private func saveVideoToTemporaryFile(data: Data) throws -> URL {
        let filename = "pictunes_\(UUID().uuidString.prefix(8)).mp4"
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(filename)
        try data.write(to: tmp, options: .atomic)
        return tmp
    }

    // MARK: - Mock + URL helpers

    private func switchToMockDueTo(_ error: Error, completion: @escaping (Result<UploadResponse, Error>) -> Void) {
        lastUsedMock = true
        returnMock(after: 0.2, completion: completion)
    }

    private func returnMock(after delay: TimeInterval, completion: @escaping (Result<UploadResponse, Error>) -> Void) {
        let mock = UploadResponse(
            label: "beach sunset",
            music: [
                Music(title: "Clair de Lune", composer: "Debussy", start: 30, end: 60, link: "https://www.youtube.com/watch?v=CvFH_6DNRCY"),
                Music(title: "Gymnopédie No.1", composer: "Erik Satie", start: 10, end: 45, link: "https://www.youtube.com/watch?v=S-Xm7s9eGxU")
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

    // 將任意字串轉為可下載的絕對網址；支援 "./dataset/..", "/dataset/..", "dataset/.."
    private func absolutizeString(_ s: String) -> URL? {
        // 已經是完整 URL
        if let u = URL(string: s), u.scheme != nil { return u }

        // 規範化相對路徑
        let norm = normalizedRelativeDatasetPath(s)

        // 優先使用 publicImageRootPath
        let withRoot = norm.hasPrefix("/") ? String(norm.dropFirst()) : norm
        let primary = baseURL.appendingPathComponent(withRoot)
        return primary
    }

    private func normalizedRelativeDatasetPath(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        // 去掉前導 "./"
        if s.hasPrefix("./") { s.removeFirst(2) }
        // 去掉多餘前導 "/"
        while s.hasPrefix("/") { s.removeFirst() }

        // 已經是 image/ 前綴，直接加一個 "/" 回去
        if s.lowercased().hasPrefix("image/") {
            return "/\(s)"
        }
        // static/ 前綴也視為已決定的公開根
        if s.lowercased().hasPrefix("static/") {
            return "/\(s)"
        }
        // 若是 dataset/ 前綴，改掛到我們設定的公開根路徑（例如 /image）
        if s.lowercased().hasPrefix("dataset/") {
            let root = publicImageRootPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return "/\(root)/\(s.dropFirst("dataset/".count))"
        }

        // 其他相對路徑，一律接在公開根路徑後面
        let root = publicImageRootPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return "/\(root)/\(s)"
    }



    // 遞迴在任意深度尋找可能的清單鍵
    private func deepFirstArray(in dict: [String:Any]) -> [[String:Any]]? {
        // 新增 top_10_matches / all_top_matches / all_class_matches 等鍵名
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

        // 繼續向下鑽
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


    // 將任意字典陣列轉 SimilarItem，容忍多種鍵名；若只有 filename 與 class，會自動組成 /dataset/{class}/{filename}.jpg
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
            if name.lowercased().hasSuffix(".jpg") || name.lowercased().hasSuffix(".jpeg") || name.lowercased().hasSuffix(".png") {
                return name
            }
            return name + ".jpg"
        }

        return arr.compactMap { d in
            // 可能的來源欄位
            let urlStr  = str(d, ["image_url","imageUrl","full_path","url","path","imagePath"])
            let label   = str(d, ["label","class","title","name"])
            let style   = str(d, ["style"])
            var file    = str(d, ["filename","file","id"])
            let score   = dbl(d, ["score","similarity","sim","prob"]) ?? 0

            // 1) 若已有可用網址或相對路徑
            if let s = urlStr, let abs = absolutizeString(s) {
                if file == nil { file = abs.lastPathComponent }
                return SimilarItem(imageUrl: abs, score: score, label: label, style: style, filename: file)
            }

            // 2) 沒有網址但有 filename 與 class，自己組成 /dataset/{class}/{filename}.jpg
            if let filename = file ?? str(d, ["id"]),
               let cls = label {
                let sanitizedClass = cls.replacingOccurrences(of: " ", with: "_")
                let relative = "dataset/\(sanitizedClass)/\(ensureJpg(filename))"
                if let abs = absolutizeString(relative) {
                    return SimilarItem(imageUrl: abs, score: score, label: label, style: style, filename: filename)
                }
            }

            // 3) 仍然沒有可用網址，用隨機圖做最後保底，至少不會留空
            let seed = file ?? label ?? "img"
            let fallback = URL(string: "https://picsum.photos/seed/\(seed)/600/400")!
            return SimilarItem(imageUrl: fallback, score: score, label: label, style: style, filename: file)
        }
    }


    // 產生壓縮 JPEG：等比縮到最長邊 maxPixel，再壓品質；若仍超過 4MB 再降品質
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

    private func clog(_ message: String) {
        print("[Pictunes] \(message)")
        logger.info("\(message, privacy: .public)")
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
