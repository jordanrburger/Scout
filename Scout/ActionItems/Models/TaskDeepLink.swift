import Foundation

enum TaskDeepLink: Equatable, Hashable, Sendable, Identifiable {
    case linear(id: String)
    case githubPR(repo: String, number: Int, rawURL: URL)
    case slackThread(URL)

    var id: String {
        switch self {
        case .linear(let id):             return "linear:\(id)"
        case .githubPR(let repo, let n, _): return "gh:\(repo)#\(n)"
        case .slackThread(let url):       return "slack:\(url.absoluteString)"
        }
    }

    var displayLabel: String {
        switch self {
        case .linear(let id):             return "Linear \(id)"
        case .githubPR(let repo, let n, _): return "PR \(repo)#\(n)"
        case .slackThread:                return "Slack thread"
        }
    }

    var openURL: URL {
        switch self {
        case .linear(let id):
            let workspace = UserDefaults.standard.string(forKey: "linearWorkspace") ?? ""
            if workspace.isEmpty {
                return URL(string: "https://linear.app/")!
            }
            return URL(string: "https://linear.app/\(workspace)/issue/\(id)")!
        case .githubPR(_, _, let raw):
            return raw
        case .slackThread(let url):
            return url
        }
    }
}
