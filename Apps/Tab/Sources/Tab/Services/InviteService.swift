import Foundation
import Supabase
import os

private let inviteLog = Logger(subsystem: "com.rithwikshetty.tab", category: "invite")

struct InviteLink: Equatable, Sendable {
    let tripID: UUID
    let inviteID: UUID
    let token: String
    let expiresAt: Date
    let url: URL
}

struct ParsedInvite: Equatable, Sendable {
    let tripID: UUID
    let inviteID: UUID
    let token: String
}

enum InviteError: LocalizedError {
    case emptyResponse
    case malformedLink

    var errorDescription: String? {
        switch self {
        case .emptyResponse: "Couldn't create an invite link. Try again."
        case .malformedLink:  "That invite link is malformed."
        }
    }
}

@MainActor
@Observable
final class InviteService {
    /// An invite URL we picked up before auth was ready, or before navigation could consume it.
    var pending: ParsedInvite?

    private let client = SupabaseClientProvider.shared

    func createInvite(tripID: UUID) async throws -> InviteLink {
        let rows: [InviteCreatedDTO] = try await client
            .rpc("create_trip_invite", params: [
                "p_trip_id": AnyJSON.string(tripID.uuidString),
            ])
            .execute()
            .value

        guard let row = rows.first else {
            inviteLog.error("create_trip_invite returned no rows")
            throw InviteError.emptyResponse
        }
        return InviteLink(
            tripID: row.tripID,
            inviteID: row.inviteID,
            token: row.token,
            expiresAt: row.expiresAt,
            url: Self.makeURL(tripID: row.tripID, inviteID: row.inviteID, token: row.token)
        )
    }

    func joinTrip(_ invite: ParsedInvite) async throws {
        try await client
            .rpc("join_trip_with_invite", params: [
                "p_trip_id":   AnyJSON.string(invite.tripID.uuidString),
                "p_invite_id": AnyJSON.string(invite.inviteID.uuidString),
                "p_token":     AnyJSON.string(invite.token),
            ])
            .execute()
    }

    /// Parses an incoming `tab://invite?...` URL and stashes it for the next signed-in render.
    @discardableResult
    func handleOpenURL(_ url: URL) -> Bool {
        guard let parsed = Self.parse(url) else { return false }
        pending = parsed
        return true
    }

    func consumePending() -> ParsedInvite? {
        defer { pending = nil }
        return pending
    }

    static func makeURL(tripID: UUID, inviteID: UUID, token: String) -> URL {
        var comps = URLComponents()
        comps.scheme = "tab"
        comps.host = "invite"
        comps.queryItems = [
            URLQueryItem(name: "trip",  value: tripID.uuidString),
            URLQueryItem(name: "id",    value: inviteID.uuidString),
            URLQueryItem(name: "token", value: token),
        ]
        return comps.url!
    }

    static func parse(_ url: URL) -> ParsedInvite? {
        guard url.scheme?.lowercased() == "tab",
              url.host?.lowercased() == "invite",
              let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }
        let items = comps.queryItems ?? []
        guard
            let tripStr = items.first(where: { $0.name == "trip" })?.value,
            let idStr   = items.first(where: { $0.name == "id" })?.value,
            let token   = items.first(where: { $0.name == "token" })?.value,
            let tripID   = UUID(uuidString: tripStr),
            let inviteID = UUID(uuidString: idStr),
            token.count >= 32
        else { return nil }
        return ParsedInvite(tripID: tripID, inviteID: inviteID, token: token)
    }
}

private struct InviteCreatedDTO: Decodable, Sendable {
    let tripID: UUID
    let inviteID: UUID
    let token: String
    let expiresAt: Date

    enum CodingKeys: String, CodingKey {
        case tripID    = "trip_id"
        case inviteID  = "invite_id"
        case token
        case expiresAt = "expires_at"
    }
}
