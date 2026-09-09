import Testing
@testable import PaguroCore

struct BlocklistSupportTests {
    @Test
    func identifierIsStableAndContentAddressed() {
        let first = BlocklistSupport.identifier(prefix: "hz", forJSON: "[1,2,3]")
        let same = BlocklistSupport.identifier(prefix: "hz", forJSON: "[1,2,3]")
        let changed = BlocklistSupport.identifier(prefix: "hz", forJSON: "[1,2,4]")

        #expect(first == same)
        #expect(first != changed)
        #expect(first.hasPrefix("hz-"))
    }

    @Test
    func ruleCountAndChunkingGuardUseTheGivenCapacity() throws {
        let json = "[{\"x\":1},{\"x\":2},{\"x\":3}]"

        #expect(try BlocklistSupport.ruleCount(inJSON: json) == 3)
        #expect(try BlocklistSupport.ruleCount(inJSON: "{\"x\":1}") == 0)
        #expect(BlocklistSupport.needsChunking(count: 3, cap: 5) == false)
        #expect(BlocklistSupport.needsChunking(count: 6, cap: 5))
    }

    @Test
    func listWithinCapacityKeepsItsOriginalJSON() throws {
        let json = "[{\"x\":1},{\"x\":2}]"
        #expect(try BlocklistSupport.chunk(json: json, cap: 10) == [json])
    }

    @Test
    func oversizedListSplitsWithoutLosingRules() throws {
        let rules = (0..<7).map { "{\"x\":\($0)}" }.joined(separator: ",")
        let chunks = try BlocklistSupport.chunk(json: "[\(rules)]", cap: 3)

        #expect(chunks.count == 3)
        let total = try chunks.reduce(0) {
            $0 + (try BlocklistSupport.ruleCount(inJSON: $1))
        }
        #expect(total == 7)
    }

    @Test
    func invalidInputsThrowSpecificErrors() {
        #expect(throws: BlocklistSupport.BlocklistError.notAnArray) {
            try BlocklistSupport.chunk(json: "{\"not\":\"an array\"}")
        }
        #expect(throws: BlocklistSupport.BlocklistError.invalidCap) {
            try BlocklistSupport.chunk(json: "[]", cap: 0)
        }
    }
}
