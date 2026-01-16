import Foundation
import os

private let openAILogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "doodledo",
    category: "OpenAIImageService"
)

struct OpenAIImageService {
    let apiKey: String
    let session: URLSession

    init(apiKey: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }

    func editImage(imageData: Data, maskData: Data?, prompt: String, size: String = "auto") async throws -> Data {
        guard let url = URL(string: "https://api.openai.com/v1/images/edits") else {
            throw OpenAIImageServiceError.invalidRequest
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.appendFormField(named: "model", value: "gpt-image-1.5", boundary: boundary)
        body.appendFormField(named: "prompt", value: prompt, boundary: boundary)
        body.appendFormField(named: "size", value: size, boundary: boundary)
        body.appendFormField(named: "quality", value: "auto", boundary: boundary)
        body.appendFormField(named: "output_format", value: "png", boundary: boundary)
        body.appendFileField(
            named: "image",
            filename: "doodle.png",
            mimeType: "image/png",
            fileData: imageData,
            boundary: boundary
        )
        if let maskData {
            body.appendFileField(
                named: "mask",
                filename: "mask.png",
                mimeType: "image/png",
                fileData: maskData,
                boundary: boundary
            )
        }
        body.appendString("--\(boundary)--\r\n")
        request.httpBody = body

        openAILogger.info(
            "Image edit request starting. imageBytes=\(imageData.count), maskBytes=\(maskData?.count ?? 0), promptLength=\(prompt.count), size=\(size)"
        )

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIImageServiceError.invalidResponse
        }

        let requestID = httpResponse.value(forHTTPHeaderField: "x-request-id") ?? "n/a"
        guard (200..<300).contains(httpResponse.statusCode) else {
            let bodyString = String(data: data, encoding: .utf8)
            openAILogger.error(
                "Image edit failed. status=\(httpResponse.statusCode) requestId=\(requestID) body=\(bodyString ?? "n/a")"
            )
            if let errorResponse = try? JSONDecoder().decode(OpenAIErrorResponse.self, from: data) {
                throw OpenAIImageServiceError.apiError(errorResponse.error.message)
            }
            throw OpenAIImageServiceError.httpError(httpResponse.statusCode)
        }

        openAILogger.info("Image edit succeeded. status=\(httpResponse.statusCode) requestId=\(requestID)")

        let imagesResponse = try JSONDecoder().decode(ImagesResponse.self, from: data)
        guard let imageBase64 = imagesResponse.data.first?.b64_json,
              let imageData = Data(base64Encoded: imageBase64) else {
            throw OpenAIImageServiceError.missingImage
        }

        return imageData
    }
}

private struct ImagesResponse: Decodable {
    struct ImageData: Decodable {
        let b64_json: String?
    }

    let data: [ImageData]
}

private struct OpenAIErrorResponse: Decodable {
    struct ErrorDetail: Decodable {
        let message: String
    }

    let error: ErrorDetail
}

enum OpenAIImageServiceError: LocalizedError {
    case invalidRequest
    case invalidResponse
    case httpError(Int)
    case apiError(String)
    case missingImage

    var errorDescription: String? {
        switch self {
        case .invalidRequest:
            return "Invalid image request."
        case .invalidResponse:
            return "Unexpected response from the image API."
        case .httpError(let code):
            return "Image API failed with status \(code)."
        case .apiError(let message):
            return message
        case .missingImage:
            return "No image data returned from the image API."
        }
    }
}

private extension Data {
    mutating func appendString(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }

    mutating func appendFormField(named name: String, value: String, boundary: String) {
        appendString("--\(boundary)\r\n")
        appendString("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        appendString("\(value)\r\n")
    }

    mutating func appendFileField(
        named name: String,
        filename: String,
        mimeType: String,
        fileData: Data,
        boundary: String
    ) {
        appendString("--\(boundary)\r\n")
        appendString("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n")
        appendString("Content-Type: \(mimeType)\r\n\r\n")
        append(fileData)
        appendString("\r\n")
    }
}
