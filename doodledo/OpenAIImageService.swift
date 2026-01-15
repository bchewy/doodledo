import Foundation

struct OpenAIImageService {
    let apiKey: String
    let session: URLSession

    init(apiKey: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }

    func editImage(imageData: Data, maskData: Data?, prompt: String) async throws -> Data {
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
        body.appendFormField(named: "size", value: "auto", boundary: boundary)
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

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIImageServiceError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            if let errorResponse = try? JSONDecoder().decode(OpenAIErrorResponse.self, from: data) {
                throw OpenAIImageServiceError.apiError(errorResponse.error.message)
            }
            throw OpenAIImageServiceError.httpError(httpResponse.statusCode)
        }

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
