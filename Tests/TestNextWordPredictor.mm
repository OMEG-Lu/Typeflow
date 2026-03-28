#import "ConversionEngine.h"
#import "NextWordPredictor.h"
#import <XCTest/XCTest.h>

@interface TestNextWordPredictor : XCTestCase
@property ConversionEngine *engine;
@end

@implementation TestNextWordPredictor

- (void)setUp {
    self.engine = [ConversionEngine sharedEngine];
    // Enable mock mode for testing (no llama.cpp needed)
    [[NextWordPredictor shared] enableMockModeWithWordData:self.engine.wordsWithFrequencyAndTranslation];
}

- (void)tearDown {
    [[NextWordPredictor shared] cancelPendingPrediction];
}

#pragma mark - Mock Mode Tests

- (void)testMockModeEnabled {
    XCTAssertTrue([NextWordPredictor shared].isModelLoaded);
    XCTAssertTrue([NextWordPredictor shared].isMockMode);
}

- (void)testPredictAfterHello {
    XCTestExpectation *exp = [self expectationWithDescription:@"prediction"];

    [[NextWordPredictor shared] predictNextWords:@"hello"
                                           count:6
                                      completion:^(NSArray<NSString *> *predictions) {
                                          XCTAssertNotNil(predictions);
                                          XCTAssertTrue(predictions.count >= 1, @"Should return at least 1 prediction");
                                          XCTAssertTrue(predictions.count <= 6, @"Should return at most 6 predictions");

                                          // "hello" should predict "world" as one of the top results
                                          NSLog(@"Predictions for 'hello': %@", predictions);
                                          XCTAssertTrue([predictions containsObject:@"world"],
                                                        @"'world' should be a prediction after 'hello'");
                                          [exp fulfill];
                                      }];

    [self waitForExpectationsWithTimeout:5.0 handler:nil];
}

- (void)testPredictAfterI {
    XCTestExpectation *exp = [self expectationWithDescription:@"prediction"];

    [[NextWordPredictor shared] predictNextWords:@"I"
                                           count:6
                                      completion:^(NSArray<NSString *> *predictions) {
                                          XCTAssertNotNil(predictions);
                                          XCTAssertTrue(predictions.count >= 1);

                                          NSLog(@"Predictions for 'I': %@", predictions);
                                          // Common words after "I": am, have, think, want, will
                                          BOOL hasCommonFollowUp = [predictions containsObject:@"am"] || [predictions containsObject:@"have"] ||
                                                                   [predictions containsObject:@"think"] || [predictions containsObject:@"want"];
                                          XCTAssertTrue(hasCommonFollowUp, @"Should predict common words after 'I'");
                                          [exp fulfill];
                                      }];

    [self waitForExpectationsWithTimeout:5.0 handler:nil];
}

- (void)testPredictMultiWordContext {
    XCTestExpectation *exp = [self expectationWithDescription:@"prediction"];

    [[NextWordPredictor shared] predictNextWords:@"I have"
                                           count:6
                                      completion:^(NSArray<NSString *> *predictions) {
                                          XCTAssertNotNil(predictions);
                                          XCTAssertTrue(predictions.count >= 1);

                                          NSLog(@"Predictions for 'I have': %@", predictions);
                                          // After "have": been, to, a, the, not
                                          BOOL hasCommonFollowUp = [predictions containsObject:@"been"] || [predictions containsObject:@"to"] ||
                                                                   [predictions containsObject:@"a"] || [predictions containsObject:@"not"];
                                          XCTAssertTrue(hasCommonFollowUp, @"Should predict common words after 'have'");
                                          [exp fulfill];
                                      }];

    [self waitForExpectationsWithTimeout:5.0 handler:nil];
}

- (void)testPredictReturnsRequestedCount {
    XCTestExpectation *exp = [self expectationWithDescription:@"prediction"];

    [[NextWordPredictor shared] predictNextWords:@"the"
                                           count:6
                                      completion:^(NSArray<NSString *> *predictions) {
                                          XCTAssertNotNil(predictions);
                                          XCTAssertEqual(predictions.count, 6, @"Should return exactly 6 predictions");
                                          NSLog(@"Predictions for 'the' (count=6): %@", predictions);
                                          [exp fulfill];
                                      }];

    [self waitForExpectationsWithTimeout:5.0 handler:nil];
}

- (void)testPredictNoDuplicates {
    XCTestExpectation *exp = [self expectationWithDescription:@"prediction"];

    [[NextWordPredictor shared] predictNextWords:@"we"
                                           count:6
                                      completion:^(NSArray<NSString *> *predictions) {
                                          XCTAssertNotNil(predictions);
                                          NSSet *uniqueSet = [NSSet setWithArray:predictions];
                                          XCTAssertEqual(uniqueSet.count, predictions.count, @"Predictions should have no duplicates");
                                          [exp fulfill];
                                      }];

    [self waitForExpectationsWithTimeout:5.0 handler:nil];
}

- (void)testPredictEmptyContext {
    XCTestExpectation *exp = [self expectationWithDescription:@"prediction"];

    [[NextWordPredictor shared] predictNextWords:@""
                                           count:6
                                      completion:^(NSArray<NSString *> *predictions) {
                                          // Empty context should return empty or nil
                                          XCTAssertTrue(predictions == nil || predictions.count == 0,
                                                        @"Empty context should return no predictions");
                                          [exp fulfill];
                                      }];

    [self waitForExpectationsWithTimeout:5.0 handler:nil];
}

- (void)testCancelPrediction {
    XCTestExpectation *exp = [self expectationWithDescription:@"cancelled"];

    [[NextWordPredictor shared] predictNextWords:@"hello world this is a test"
                                           count:6
                                      completion:^(NSArray<NSString *> *predictions) {
                                          // May return nil if cancelled, or results if it completed before cancel
                                          [exp fulfill];
                                      }];

    // Cancel immediately
    [[NextWordPredictor shared] cancelPendingPrediction];

    [self waitForExpectationsWithTimeout:5.0 handler:nil];
}

#pragma mark - Model Path Tests

- (void)testModelDirectoryPath {
    NSString *path = [NextWordPredictor modelDirectoryPath];
    XCTAssertNotNil(path);
    XCTAssertTrue([path containsString:@"Typeflow/models"], @"Path should contain Typeflow/models");
}

- (void)testModelFilenames {
    XCTAssertTrue([[NextWordPredictor modelFilenameForTier:LLMModelTierSmall] containsString:@"smollm"]);
    XCTAssertTrue([[NextWordPredictor modelFilenameForTier:LLMModelTierMedium] containsString:@"qwen2-0.5b"]);
    XCTAssertTrue([[NextWordPredictor modelFilenameForTier:LLMModelTierLarge] containsString:@"qwen2-1.5b"]);
}

#pragma mark - Unload Tests

- (void)testUnloadAndReload {
    XCTAssertTrue([NextWordPredictor shared].isModelLoaded);

    [[NextWordPredictor shared] unloadModel];
    XCTAssertFalse([NextWordPredictor shared].isModelLoaded);

    // Re-enable mock mode
    [[NextWordPredictor shared] enableMockModeWithWordData:self.engine.wordsWithFrequencyAndTranslation];
    XCTAssertTrue([NextWordPredictor shared].isModelLoaded);
    XCTAssertTrue([NextWordPredictor shared].isMockMode);
}

@end
