// PictunesCore.swift
import Foundation
import UIKit

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

    private enum CodingKeys: String, CodingKey {
        case imageUrl, score, label
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

// MARK: - Domain (anime/film)

public enum RecommendationDomain: String, Codable, CaseIterable {
    case anime
    case film
}

// MARK: - Debug state

public enum PictunesDebugState: Equatable {
    case idle
    case requesting
    case success(similarCount: Int, usedMock: Bool, httpStatus: Int?)
    case failure(message: String, httpStatus: Int?, dataSnippet: String?)
}

// MARK: - Service

public final class PictunesService {
    public static let shared = PictunesService()

    public enum Mode {
        case live          // always call backend
        case mock          // always return local mock data
        case autoFallback  // try backend; on failure return mock
    }

    public var mode: Mode = .autoFallback

    public private(set) var lastRequestUsedMock: Bool = false
    public private(set) var debugState: PictunesDebugState = .idle

    // Backend base URL
    private let baseURL = URL(string: "http://172.20.10.2:5001")!

    // Endpoints
    private var uploadEndpoint: URL { baseURL.appendingPathComponent("upload") }
    private var renderEndpoint: URL { baseURL.appendingPathComponent("render") }

    // URLSession
    private lazy var urlSession: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 20
        cfg.timeoutIntervalForResource = 60
        return URLSession(configuration: cfg)
    }()

    private init() {}

    // MARK: Public API

    /// Upload image with selected domain (anime/film)
    public func upload(image: UIImage,
                       domain: RecommendationDomain,
                       completion: @escaping (Result<UploadResponse, Error>) -> Void) {
        switch mode {
        case .mock:
            self.lastRequestUsedMock = true
            self.debugState = .requesting
            return self.returnMock(after: 0.3, completion: completion)

        case .live:
            self.performLiveUpload(image: image, domain: domain, fallbackToMock: false, completion: completion)

        case .autoFallback:
            self.performLiveUpload(image: image, domain: domain, fallbackToMock: true, completion: completion)
        }
    }

    /// Generate 15s video for the selected track and image
    public func generateVideo(image: UIImage,
                              domain: RecommendationDomain,
                              track: Music,
                              completion: @escaping (Result<URL, Error>) -> Void) {
        switch mode {
        case .mock:
            self.lastRequestUsedMock = true
            // Return a sample video url
            let mockURL = URL(string: "https://filesamples.com/samples/video/mp4/sample_960x400_ocean_with_audio.mp4")!
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                completion(.success(mockURL))
            }
        case .live, .autoFallback:
            performLiveRender(image: image, domain: domain, track: track, fallbackToMock: (mode == .autoFallback), completion: completion)
        }
    }

    public func healthCheck(completion: @escaping (Bool) -> Void) {
        let url = baseURL.appendingPathComponent("health")
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        urlSession.dataTask(with: req) { _, resp, _ in
            let ok = (resp as? HTTPURLResponse)?.statusCode == 200
            DispatchQueue.main.async { completion(ok) }
        }.resume()
    }

    public var debugSummary: String {
        switch debugState {
        case .idle:
            return "狀態：Idle"
        case .requesting:
            return "狀態：Requesting..."
        case .success(let count, let usedMock, let code):
            let src = usedMock ? "Mock" : "Live"
            let http = code != nil ? "HTTP \(code!)" : "HTTP -"
            return "成功：\(src)，\(http)，similar=\(count)"
        case .failure(let msg, let code, _):
            let http = code != nil ? "HTTP \(code!)" : "HTTP -"
            return "失敗：\(http)，\(msg)"
        }
    }

    // MARK: - Internal

    private func performLiveUpload(image: UIImage,
                                   domain: RecommendationDomain,
                                   fallbackToMock: Bool,
                                   completion: @escaping (Result<UploadResponse, Error>) -> Void) {
        self.lastRequestUsedMock = false
        self.debugState = .requesting

        guard let jpegData = image.jpegData(compressionQuality: 0.8) else {
            let err = NSError(domain: "PictunesService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Cannot convert image to JPEG"])
            self.debugState = .failure(message: err.localizedDescription, httpStatus: nil, dataSnippet: nil)
            DispatchQueue.main.async { completion(.failure(err)) }
            return
        }

        var request = URLRequest(url: uploadEndpoint)
        request.httpMethod = "POST"
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        // Part 1: image
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"image.jpg\"\r\n")
        body.append("Content-Type: image/jpeg\r\n\r\n")
        body.append(jpegData)
        body.append("\r\n")

        // Part 2: domain
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"domain\"\r\n\r\n")
        body.append(domain.rawValue)
        body.append("\r\n")

        // Close boundary
        body.append("--\(boundary)--\r\n")

        urlSession.uploadTask(with: request, from: body) { data, response, error in
            let httpCode = (response as? HTTPURLResponse)?.statusCode
            if let error = error {
                if fallbackToMock {
                    self.debugState = .failure(message: error.localizedDescription, httpStatus: httpCode, dataSnippet: nil)
                    self.switchToMockDueTo(error, completion: completion)
                } else {
                    self.debugState = .failure(message: error.localizedDescription, httpStatus: httpCode, dataSnippet: nil)
                    DispatchQueue.main.async { completion(.failure(error)) }
                }
                return
            }

            if let code = httpCode, code != 200 {
                let statusError = NSError(domain: "PictunesService", code: code, userInfo: [NSLocalizedDescriptionKey: "Unexpected status code: \(code)"])
                if fallbackToMock {
                    self.debugState = .failure(message: statusError.localizedDescription, httpStatus: httpCode, dataSnippet: nil)
                    self.switchToMockDueTo(statusError, completion: completion)
                } else {
                    self.debugState = .failure(message: statusError.localizedDescription, httpStatus: httpCode, dataSnippet: nil)
                    DispatchQueue.main.async { completion(.failure(statusError)) }
                }
                return
            }

            guard let data = data else {
                let dataError = NSError(domain: "PictunesService", code: -2, userInfo: [NSLocalizedDescriptionKey: "No response body"])
                if fallbackToMock {
                    self.debugState = .failure(message: dataError.localizedDescription, httpStatus: httpCode, dataSnippet: nil)
                    self.switchToMockDueTo(dataError, completion: completion)
                } else {
                    self.debugState = .failure(message: dataError.localizedDescription, httpStatus: httpCode, dataSnippet: nil)
                    DispatchQueue.main.async { completion(.failure(dataError)) }
                }
                return
            }

            do {
                var decoded = try JSONDecoder().decode(UploadResponse.self, from: data)
                decoded = self.normalizeURLs(in: decoded)
                let count = decoded.similar?.count ?? 0
                self.debugState = .success(similarCount: count, usedMock: false, httpStatus: httpCode)
                DispatchQueue.main.async { completion(.success(decoded)) }
            } catch {
                let snippet = String(data: data, encoding: .utf8).flatMap { String($0.prefix(500)) }
                if fallbackToMock {
                    self.debugState = .failure(message: error.localizedDescription, httpStatus: httpCode, dataSnippet: snippet)
                    self.switchToMockDueTo(error, completion: completion)
                } else {
                    self.debugState = .failure(message: error.localizedDescription, httpStatus: httpCode, dataSnippet: snippet)
                    DispatchQueue.main.async { completion(.failure(error)) }
                }
            }
        }.resume()
    }

    private func performLiveRender(image: UIImage,
                                   domain: RecommendationDomain,
                                   track: Music,
                                   fallbackToMock: Bool,
                                   completion: @escaping (Result<URL, Error>) -> Void) {
        self.lastRequestUsedMock = false
        self.debugState = .requesting

        guard let jpegData = image.jpegData(compressionQuality: 0.8) else {
            let err = NSError(domain: "PictunesService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Cannot convert image to JPEG"])
            DispatchQueue.main.async { completion(.failure(err)) }
            return
        }

        // Build multipart with image + domain + track(json)
        var req = URLRequest(url: renderEndpoint)
        req.httpMethod = "POST"
        let boundary = UUID().uuidString
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        // image
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"image.jpg\"\r\n")
        body.append("Content-Type: image/jpeg\r\n\r\n")
        body.append(jpegData)
        body.append("\r\n")
        // domain
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"domain\"\r\n\r\n")
        body.append(domain.rawValue)
        body.append("\r\n")
        // track json
        let trackJSON = (try? JSONEncoder().encode(track)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"track\"\r\n\r\n")
        body.append(trackJSON)
        body.append("\r\n")
        // close
        body.append("--\(boundary)--\r\n")

        struct RenderResponse: Codable { let videoUrl: URL? }

        urlSession.uploadTask(with: req, from: body) { data, response, error in
            let httpCode = (response as? HTTPURLResponse)?.statusCode
            if let error = error {
                if fallbackToMock {
                    let mockURL = URL(string: "https://filesamples.com/samples/video/mp4/sample_960x400_ocean_with_audio.mp4")!
                    self.lastRequestUsedMock = true
                    DispatchQueue.main.async { completion(.success(mockURL)) }
                } else {
                    DispatchQueue.main.async { completion(.failure(error)) }
                }
                return
            }

            guard let code = httpCode, code == 200, let data = data else {
                let err = NSError(domain: "PictunesService", code: httpCode ?? -3, userInfo: [NSLocalizedDescriptionKey: "Render failed"])
                if fallbackToMock {
                    let mockURL = URL(string: "https://filesamples.com/samples/video/mp4/sample_960x400_ocean_with_audio.mp4")!
                    self.lastRequestUsedMock = true
                    DispatchQueue.main.async { completion(.success(mockURL)) }
                } else {
                    DispatchQueue.main.async { completion(.failure(err)) }
                }
                return
            }

            do {
                let resp = try JSONDecoder().decode(RenderResponse.self, from: data)
                guard let raw = resp.videoUrl else {
                    let err = NSError(domain: "PictunesService", code: -4, userInfo: [NSLocalizedDescriptionKey: "No videoUrl in response"])
                    DispatchQueue.main.async { completion(.failure(err)) }
                    return
                }
                let url = self.absolutize(raw) ?? raw
                DispatchQueue.main.async { completion(.success(url)) }
            } catch {
                if fallbackToMock {
                    let mockURL = URL(string: "https://filesamples.com/samples/video/mp4/sample_960x400_ocean_with_audio.mp4")!
                    self.lastRequestUsedMock = true
                    DispatchQueue.main.async { completion(.success(mockURL)) }
                } else {
                    DispatchQueue.main.async { completion(.failure(error)) }
                }
            }
        }.resume()
    }

    private func switchToMockDueTo(_ error: Error, completion: @escaping (Result<UploadResponse, Error>) -> Void) {
        self.lastRequestUsedMock = true
        self.returnMock(after: 0.2, completion: completion)
    }

    private func returnMock(after delay: TimeInterval, completion: @escaping (Result<UploadResponse, Error>) -> Void) {
        let mock = UploadResponse(
            label: "beach sunset",
            music: [
                Music(title: "Clair de Lune", composer: "Debussy", start: 30, end: 60, link: "https://www.youtube.com/watch?v=CvFH_6DNRCY"),
                Music(title: "Gymnopédie No.1", composer: "Erik Satie", start: 10, end: 45, link: "https://www.youtube.com/watch?v=S-Xm7s9eGxU")
            ],
            similar: [
                SimilarItem(imageUrl: URL(string: "https://picsum.photos/seed/sim1/600/400")!, score: 0.873, label: "sunset"),
                SimilarItem(imageUrl: URL(string: "https://picsum.photos/seed/sim2/600/400")!, score: 0.842, label: "beach"),
                SimilarItem(imageUrl: URL(string: "https://picsum.photos/seed/sim3/600/400")!, score: 0.801, label: "sky")
            ],
            videoUrl: URL(string: "https://filesamples.com/samples/video/mp4/sample_960x400_ocean_with_audio.mp4")
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            self.debugState = .success(similarCount: mock.similar?.count ?? 0, usedMock: true, httpStatus: nil)
            completion(.success(mock))
        }
    }

    private func normalizeURLs(in response: UploadResponse) -> UploadResponse {
        let fixedVideo = absolutize(response.videoUrl)
        let fixedSimilar: [SimilarItem]? = response.similar?.map { item in
            let fixed = absolutize(item.imageUrl) ?? item.imageUrl
            return SimilarItem(imageUrl: fixed, score: item.score, label: item.label)
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
}

// MARK: - Data helpers

private extension Data {
    mutating func append(_ string: String) {
        if let d = string.data(using: .utf8) { append(d) }
    }
}

// MARK: - Int formatting

public extension Int {
    /// Formats seconds to "m:ss"
    var timeFormatted: String {
        let total = Swift.max(0, self)
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
