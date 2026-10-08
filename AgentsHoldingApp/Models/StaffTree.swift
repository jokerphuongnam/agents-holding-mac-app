import Foundation

/// Org tree node: CEO → reports → … (hop chain).
struct StaffTreeNode: Identifiable, Hashable {
    /// Unique per placement. One staff can sit under a team lead and a real lead.
    var id: String
    var staff: StaffNode
    var children: [StaffTreeNode]
}

extension StaffDirectory {
    /// Build staffs tree rooted at top dispatcher(s) (`ceo` / `holding-ceo`).
    func buildStaffTree(companyRoot: URL) -> [StaffTreeNode] {
        let agents = loadAgentsTSV(companyRoot: companyRoot)
        let all = loadTeams(companyRoot: companyRoot).flatMap(\.allStaffs)
        guard !all.isEmpty else { return [] }

        var byName: [String: StaffNode] = [:]
        for s in all { byName[s.name] = s }

        var childrenMap: [String: [StaffNode]] = [:]
        var realChildren: [String: [StaffNode]] = [:]
        var roots: [StaffNode] = []

        for staff in all {
            let lead = resolveLead(
                name: staff.name,
                row: agents[staff.name],
                agents: agents,
                companyRoot: companyRoot
            )
            if let lead, !lead.isEmpty, byName[lead] != nil, lead != staff.name {
                childrenMap[lead, default: []].append(staff)
            } else {
                roots.append(staff)
            }
            let real = resolveRealLead(name: staff.name, teamLead: lead, agents: agents)
            if let real, byName[real] != nil {
                realChildren[real, default: []].append(staff)
            }
        }

        // Prefer classic roots first
        roots.sort { a, b in
            let rank: (StaffNode) -> Int = { s in
                if s.name == "ceo" || s.name == "holding-ceo" { return 0 }
                if s.name.hasSuffix("-lead") || s.name == "cto" { return 1 }
                return 2
            }
            let ra = rank(a), rb = rank(b)
            if ra != rb { return ra < rb }
            return a.name < b.name
        }

        func build(_ staff: StaffNode, parent: String, stack: Set<String>, expand: Bool) -> StaffTreeNode {
            var nextStack = stack
            nextStack.insert(staff.name)
            let teamKids = expand
                ? (childrenMap[staff.name] ?? [])
                    .sorted { $0.name < $1.name }
                    .filter { !nextStack.contains($0.name) }
                    .map { build($0, parent: staff.name, stack: nextStack, expand: true) }
                : []
            let extraKids = expand
                ? (realChildren[staff.name] ?? [])
                    .sorted { $0.name < $1.name }
                    .filter { !nextStack.contains($0.name) }
                    .map { build($0, parent: "\(staff.name)#real", stack: nextStack, expand: false) }
                : []
            return StaffTreeNode(
                id: "\(parent)/\(staff.id)",
                staff: staff,
                children: teamKids + extraKids
            )
        }

        // If we somehow got many "roots", still show a tree starting from ceo when present.
        if let ceo = byName["holding-ceo"] ?? byName["ceo"] {
            return [build(ceo, parent: "root", stack: [], expand: true)]
        }
        return roots.map { build($0, parent: "root", stack: [], expand: true) }
    }
}
