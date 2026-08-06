import XCTest
@testable import WeeOrchestrator

final class ChatScrollFollowStateTests: XCTestCase {
    func test_startsFollowingBottom() {
        let state = ChatScrollFollowState()
        XCTAssertTrue(state.isFollowingBottom)
        XCTAssertFalse(state.hasNewContentBelow)
    }

    func test_contentChangedScrollsWhileFollowing() {
        var state = ChatScrollFollowState()
        XCTAssertTrue(state.contentChanged(), "Should scroll when the user is at the bottom")
        XCTAssertFalse(state.hasNewContentBelow)
    }

    /// The bug in #59: a streamed response growing the last message's text
    /// (no new message appended) must still trigger the same follow
    /// decision as a brand-new message would.
    func test_streamingGrowthFollowsJustLikeANewMessage() {
        var state = ChatScrollFollowState()
        state.updateProximity(anchorMaxY: 500, viewportHeight: 500) // at bottom
        XCTAssertTrue(state.contentChanged(), "Streaming growth should scroll while following, same as a new message")
    }

    func test_scrollingAwayStopsFollowingAndSurfacesNewContentPill() {
        var state = ChatScrollFollowState()
        // User scrolled up: anchor is far below the viewport bottom.
        state.updateProximity(anchorMaxY: 2000, viewportHeight: 500)
        XCTAssertFalse(state.isFollowingBottom)

        let shouldScroll = state.contentChanged()
        XCTAssertFalse(shouldScroll, "Must not forcibly move the user once they've scrolled away")
        XCTAssertTrue(state.hasNewContentBelow, "New content should be surfaced via the pill instead")
    }

    func test_scrollingBackToBottomClearsThePill() {
        var state = ChatScrollFollowState()
        state.updateProximity(anchorMaxY: 2000, viewportHeight: 500)
        state.contentChanged()
        XCTAssertTrue(state.hasNewContentBelow)

        // User scrolls back down on their own.
        state.updateProximity(anchorMaxY: 500, viewportHeight: 500)
        XCTAssertTrue(state.isFollowingBottom)
        XCTAssertFalse(state.hasNewContentBelow)
    }

    func test_proximityThresholdCountsNearBottomAsFollowing() {
        var state = ChatScrollFollowState()
        let withinThreshold = ChatScrollFollowState.bottomProximityThreshold - 1
        state.updateProximity(anchorMaxY: 500 + withinThreshold, viewportHeight: 500)
        XCTAssertTrue(state.isFollowingBottom)

        let beyondThreshold = ChatScrollFollowState.bottomProximityThreshold + 1
        state.updateProximity(anchorMaxY: 500 + beyondThreshold, viewportHeight: 500)
        XCTAssertFalse(state.isFollowingBottom)
    }

    func test_jumpToBottomResetsState() {
        var state = ChatScrollFollowState()
        state.updateProximity(anchorMaxY: 2000, viewportHeight: 500)
        state.contentChanged()
        XCTAssertTrue(state.hasNewContentBelow)
        XCTAssertFalse(state.isFollowingBottom)

        state.jumpToBottom()
        XCTAssertTrue(state.isFollowingBottom)
        XCTAssertFalse(state.hasNewContentBelow)
    }

    func test_multipleContentChangesWhileAwayOnlyNeedOnePillDismissal() {
        var state = ChatScrollFollowState()
        state.updateProximity(anchorMaxY: 2000, viewportHeight: 500)
        state.contentChanged() // message 1 arrives
        state.contentChanged() // message 2 arrives, still scrolled away
        XCTAssertTrue(state.hasNewContentBelow)

        state.jumpToBottom()
        XCTAssertFalse(state.hasNewContentBelow)
    }
}
