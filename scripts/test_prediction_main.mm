/**
 * Standalone test program for NextWordPredictor
 * Tests mock mode without any llama.cpp dependency.
 *
 * Compile: see test-prediction.sh
 */

#import "NextWordPredictor.h"
#import <Foundation/Foundation.h>
#include <dispatch/dispatch.h>
#include <stdio.h>

// ---- Simple test framework ----

static int _testsPassed = 0;
static int _testsFailed = 0;

#define TEST(name, body)                                                                                                                             \
    do {                                                                                                                                             \
        @autoreleasepool {                                                                                                                           \
            printf("  TEST: %-45s ", name);                                                                                                          \
            @try {                                                                                                                                   \
                body;                                                                                                                                \
                printf("PASS\n");                                                                                                                    \
                _testsPassed++;                                                                                                                      \
            } @catch (NSException * e) {                                                                                                             \
                printf("FAIL (%s)\n", e.reason.UTF8String);                                                                                          \
                _testsFailed++;                                                                                                                      \
            }                                                                                                                                        \
        }                                                                                                                                            \
    } while (0)

#define ASSERT(cond, msg)                                                                                                                            \
    do {                                                                                                                                             \
        if (!(cond))                                                                                                                                 \
            @throw [NSException exceptionWithName:@"AssertionFailed" reason:@ msg userInfo:nil];                                                     \
    } while (0)

// ---- Synchronous prediction helper ----

static NSArray<NSString *> *predictSync(NSString *context, NSInteger count) {
    __block NSArray<NSString *> *result = nil;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);

    [[NextWordPredictor shared] predictNextWords:context
                                           count:count
                                      completion:^(NSArray<NSString *> *predictions) {
                                          result = predictions;
                                          dispatch_semaphore_signal(sem);
                                      }];

    // Wait up to 5 seconds (run main runloop to allow dispatch_async to main queue)
    NSDate *timeout = [NSDate dateWithTimeIntervalSinceNow:5.0];
    while (dispatch_semaphore_wait(sem, DISPATCH_TIME_NOW) != 0) {
        [[NSRunLoop mainRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
        if ([NSDate.date compare:timeout] == NSOrderedDescending) {
            break;
        }
    }

    return result;
}

// ---- Tests ----

static void runTests() {
    printf("--- Mock Mode Prediction Tests ---\n\n");

    // Enable mock mode
    [[NextWordPredictor shared] enableMockModeWithWordData:@{}];

    TEST("Mock mode is enabled", {
        ASSERT([NextWordPredictor shared].isModelLoaded, "Model should be loaded");
        ASSERT([NextWordPredictor shared].isMockMode, "Should be in mock mode");
    });

    TEST("Predict after 'hello'", {
        NSArray *predictions = predictSync(@"hello", 6);
        ASSERT(predictions != nil, "Predictions should not be nil");
        ASSERT(predictions.count >= 1, "Should have at least 1 prediction");
        printf("\n         Predictions: %s", [[predictions componentsJoinedByString:@", "] UTF8String]);
        printf("\n         ");
        ASSERT([predictions containsObject:@"world"], "'world' should be predicted after 'hello'");
    });

    TEST("Predict after 'I'", {
        NSArray *predictions = predictSync(@"I", 6);
        ASSERT(predictions != nil, "Predictions should not be nil");
        ASSERT(predictions.count >= 1, "Should have at least 1 prediction");
        printf("\n         Predictions: %s", [[predictions componentsJoinedByString:@", "] UTF8String]);
        printf("\n         ");
        BOOL ok = [predictions containsObject:@"am"] || [predictions containsObject:@"have"] || [predictions containsObject:@"think"];
        ASSERT(ok, "Should predict common words after 'I'");
    });

    TEST("Predict after 'I have'", {
        NSArray *predictions = predictSync(@"I have", 6);
        ASSERT(predictions != nil, "Predictions should not be nil");
        printf("\n         Predictions: %s", [[predictions componentsJoinedByString:@", "] UTF8String]);
        printf("\n         ");
        BOOL ok = [predictions containsObject:@"been"] || [predictions containsObject:@"to"] || [predictions containsObject:@"a"];
        ASSERT(ok, "Should predict common words after 'have'");
    });

    TEST("Predict after 'the'", {
        NSArray *predictions = predictSync(@"the", 6);
        ASSERT(predictions != nil, "Predictions should not be nil");
        ASSERT(predictions.count == 6, "Should return exactly 6 predictions");
        printf("\n         Predictions: %s", [[predictions componentsJoinedByString:@", "] UTF8String]);
        printf("\n         ");
    });

    TEST("Predict after 'good'", {
        NSArray *predictions = predictSync(@"good", 6);
        ASSERT(predictions != nil, "Predictions should not be nil");
        printf("\n         Predictions: %s", [[predictions componentsJoinedByString:@", "] UTF8String]);
        printf("\n         ");
        BOOL ok = [predictions containsObject:@"morning"] || [predictions containsObject:@"evening"] || [predictions containsObject:@"afternoon"];
        ASSERT(ok, "Should predict time-of-day words after 'good'");
    });

    TEST("Predict after 'thank'", {
        NSArray *predictions = predictSync(@"thank", 6);
        ASSERT(predictions != nil, "Predictions should not be nil");
        printf("\n         Predictions: %s", [[predictions componentsJoinedByString:@", "] UTF8String]);
        printf("\n         ");
        ASSERT([predictions containsObject:@"you"], "'you' should be predicted after 'thank'");
    });

    TEST("No duplicates in predictions", {
        NSArray *predictions = predictSync(@"we", 6);
        ASSERT(predictions != nil, "Predictions should not be nil");
        NSSet *unique = [NSSet setWithArray:predictions];
        ASSERT(unique.count == predictions.count, "Predictions should have no duplicates");
    });

    TEST("Empty context returns empty", {
        NSArray *predictions = predictSync(@"", 6);
        ASSERT(predictions == nil || predictions.count == 0, "Empty context should return no predictions");
    });

    TEST("Context with spaces only returns empty", {
        NSArray *predictions = predictSync(@"   ", 6);
        ASSERT(predictions == nil || predictions.count == 0, "Whitespace context should return no predictions");
    });

    TEST("Cancel prediction", {
        [[NextWordPredictor shared] predictNextWords:@"hello world"
                                               count:6
                                          completion:^(NSArray<NSString *> *predictions) {
                                              // May or may not be called
                                          }];
        [[NextWordPredictor shared] cancelPendingPrediction];
        // If we get here without hanging, the test passes
    });

    TEST("Unload and reload mock", {
        [[NextWordPredictor shared] unloadModel];
        ASSERT(![NextWordPredictor shared].isModelLoaded, "Model should be unloaded");
        [[NextWordPredictor shared] enableMockModeWithWordData:@{}];
        ASSERT([NextWordPredictor shared].isModelLoaded, "Model should be reloaded");
    });

    TEST("Model directory path is valid", {
        NSString *path = [NextWordPredictor modelDirectoryPath];
        ASSERT(path != nil, "Path should not be nil");
        ASSERT([path containsString:@"Typeflow"], "Path should contain 'Typeflow'");
        printf("\n         Path: %s", path.UTF8String);
        printf("\n         ");
    });

    TEST("Model filenames for all tiers", {
        ASSERT([[NextWordPredictor modelFilenameForTier:LLMModelTierSmall] containsString:@"smollm"], "Small tier filename");
        ASSERT([[NextWordPredictor modelFilenameForTier:LLMModelTierMedium] containsString:@"qwen2-0.5b"], "Medium tier filename");
        ASSERT([[NextWordPredictor modelFilenameForTier:LLMModelTierLarge] containsString:@"qwen2-1.5b"], "Large tier filename");
    });

    // ---- Interactive mode ----
    printf("\n--- Interactive Mode ---\n");
    printf("Type a word or phrase, press Enter to see predictions.\n");
    printf("Type 'quit' to exit.\n\n");

    char input[1024];
    while (1) {
        printf("> ");
        fflush(stdout);
        if (!fgets(input, sizeof(input), stdin))
            break;

        // Remove trailing newline
        size_t len = strlen(input);
        if (len > 0 && input[len - 1] == '\n')
            input[len - 1] = '\0';

        NSString *context = [NSString stringWithUTF8String:input];
        if ([context isEqualToString:@"quit"] || [context isEqualToString:@"exit"])
            break;

        if (context.length == 0)
            continue;

        NSArray *predictions = predictSync(context, 6);
        if (predictions && predictions.count > 0) {
            printf("  Predictions: ");
            for (int i = 0; i < (int)predictions.count; i++) {
                printf("[%d] %s  ", i + 1, [predictions[i] UTF8String]);
            }
            printf("\n");
        } else {
            printf("  (no predictions)\n");
        }
    }
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        runTests();

        printf("\n======================================\n");
        printf("  Results: %d passed, %d failed\n", _testsPassed, _testsFailed);
        printf("======================================\n");

        return _testsFailed > 0 ? 1 : 0;
    }
}
