#import <AppKit/NSSpellChecker.h>
#import <Carbon/Carbon.h>
#import <CoreServices/CoreServices.h>

#import "InputApplicationDelegate.h"
#import "InputController.h"
#import "NSScreen+PointConversion.h"
#import "PreferencesWindowController.h"

extern IMKCandidates *sharedCandidates;
extern NSUserDefaults *preference;
extern ConversionEngine *engine;

static const NSInteger kMaxContextHistoryWords = 50;
static const NSInteger kPredictionCount = 9;

typedef NSInteger KeyCode;
static const KeyCode KEY_RETURN = 36, KEY_SPACE = 49, KEY_DELETE = 51, KEY_ESC = 53, KEY_ARROW_DOWN = 125, KEY_ARROW_UP = 126, KEY_RIGHT_SHIFT = 60;

@interface InputController()

- (void)showIMEPreferences:(id)sender;
- (void)clickAbout:(NSMenuItem *)sender;
- (BOOL)isPrivacySensitiveClient:(id)client;
- (void)cancelPredictionForPrivacy;

@end

@implementation InputController

- (NSUInteger)recognizedEvents:(id)sender {
    return NSEventMaskKeyDown | NSEventMaskFlagsChanged;
}

- (BOOL)handleEvent:(NSEvent *)event client:(id)sender {
    NSUInteger modifiers = event.modifierFlags;
    bool handled = NO;
    switch (event.type) {
    case NSEventTypeFlagsChanged:
        // NSLog(@"hallelujah event modifierFlags %lu, event keyCode: %@", (unsigned long)[event modifierFlags], [event keyCode]);

        if (_lastEventTypes[1] == NSEventTypeFlagsChanged && _lastModifiers[1] == modifiers) {
            return YES;
        }

        if (modifiers == 0 && _lastEventTypes[1] == NSEventTypeFlagsChanged && _lastModifiers[1] == NSEventModifierFlagShift &&
            event.keyCode == KEY_RIGHT_SHIFT && !(_lastModifiers[0] & NSEventModifierFlagShift)) {

            _defaultEnglishMode = !_defaultEnglishMode;
            if (_defaultEnglishMode) {
                NSString *bufferedText = [self originalBuffer];
                if (bufferedText && bufferedText.length > 0) {
                    [self cancelComposition];
                    [self commitComposition:sender];
                }
                // Also exit prediction mode when switching to English mode
                [self exitPredictionMode];
            }
        }
        break;
    case NSEventTypeKeyDown:
        if ([self isPrivacySensitiveClient:sender]) {
            [self cancelPredictionForPrivacy];
        }
        // Handle ALL prediction mode keys before the English mode check,
        // because _defaultEnglishMode breaks out of the switch and skips onKeyEvent:.
        if (_predictionMode) {
            return [self handlePredictionModeKey:event client:sender];
        }

        if (_defaultEnglishMode) {
            break;
        }

        // ignore Command+X hotkeys.
        if (modifiers & NSEventModifierFlagCommand)
            break;

        if (modifiers & NSEventModifierFlagOption) {
            return false;
        }

        if (modifiers & NSEventModifierFlagControl) {
            return false;
        }

        handled = [self onKeyEvent:event client:sender];
        break;
    default:
        break;
    }

    _lastModifiers[0] = _lastModifiers[1];
    _lastEventTypes[0] = _lastEventTypes[1];
    _lastModifiers[1] = modifiers;
    _lastEventTypes[1] = event.type;
    return handled;
}

- (BOOL)onKeyEvent:(NSEvent *)event client:(id)sender {
    _currentClient = sender;
    NSInteger keyCode = event.keyCode;
    NSString *characters = event.characters;

    NSString *bufferedText = [self originalBuffer];
    bool hasBufferedText = bufferedText && bufferedText.length > 0;

    // --- Prediction mode key handling ---
    if (_predictionMode) {
        return [self handlePredictionModeKey:event client:sender];
    }

    if (keyCode == KEY_DELETE) {
        if (hasBufferedText) {
            return [self deleteBackward:sender];
        }

        return NO;
    }

    if (keyCode == KEY_SPACE) {
        if (hasBufferedText) {
            [self commitComposition:sender];
            return YES;
        }
        return NO;
    }

    if (keyCode == KEY_RETURN) {
        if (hasBufferedText) {
            [self commitCompositionWithoutSpace:sender];
            return YES;
        }
        return NO;
    }

    if (keyCode == KEY_ESC) {
        [self cancelComposition];
        [sender insertText:@""];
        [self reset];
        return YES;
    }

    char ch = [characters characterAtIndex:0];
    if ((ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z')) {
        [self originalBufferAppend:characters client:sender];

        [sharedCandidates updateCandidates];
        [sharedCandidates show:kIMKLocateCandidatesBelowHint];
        return YES;
    }

    if ([self isMojaveAndLaterSystem]) {
        BOOL isCandidatesVisible = [sharedCandidates isVisible];
        if (isCandidatesVisible) {
            if (keyCode == KEY_ARROW_DOWN) {
                [sharedCandidates moveDown:self];
                _currentCandidateIndex++;
                return NO;
            }

            if (keyCode == KEY_ARROW_UP) {
                [sharedCandidates moveUp:self];
                _currentCandidateIndex--;
                return NO;
            }
        }

        if ([[NSCharacterSet decimalDigitCharacterSet] characterIsMember:ch]) {
            if (!hasBufferedText) {
                [self appendToComposedBuffer:characters];
                [self commitCompositionWithoutSpace:sender];
                return YES;
            }

            if (isCandidatesVisible) { // use 1~9 digital numbers as selection keys
                int pressedNumber = characters.intValue;
                NSString *candidate;
                int pageSize = 9;
                if (_currentCandidateIndex <= pageSize) {
                    candidate = _candidates[pressedNumber - 1];
                } else {
                    candidate = _candidates[pageSize * (_currentCandidateIndex / pageSize - 1) + (_currentCandidateIndex % pageSize) +
                                            pressedNumber - 1];
                }
                [self cancelComposition];
                [self setComposedBuffer:candidate];
                [self setOriginalBuffer:candidate];
                [self commitComposition:sender];
                return YES;
            }
        }
    }

    if ([[NSCharacterSet punctuationCharacterSet] characterIsMember:ch] || [[NSCharacterSet symbolCharacterSet] characterIsMember:ch]) {
        if (hasBufferedText) {
            [self appendToComposedBuffer:characters];
            [self commitCompositionWithoutSpace:sender];
            return YES;
        }
    }

    return NO;
}

#pragma mark - Prediction Mode Key Handling

- (BOOL)handlePredictionModeKey:(NSEvent *)event client:(id)sender {
    NSInteger keyCode = event.keyCode;
    NSString *characters = event.characters;
    char ch = characters.length > 0 ? [characters characterAtIndex:0] : 0;

    // ESC: dismiss predictions
    if (keyCode == KEY_ESC) {
        [self exitPredictionMode];
        return YES;
    }

    // Space: select first prediction (if available)
    if (keyCode == KEY_SPACE) {
        if (_predictions && _predictions.count > 0) {
            [self selectPrediction:_predictions[0] client:sender];
            return YES;
        }
        [self exitPredictionMode];
        return NO;
    }

    // Return: set flag so candidateSelected: knows to dismiss instead of select.
    // IMKCandidates intercepts Return before we get here, so we also handle it
    // via candidateSelected:.
    if (keyCode == KEY_RETURN) {
        [self exitPredictionMode];
        return YES;
    }

    // Arrow keys: navigate prediction candidates
    if (keyCode == KEY_ARROW_DOWN) {
        [sharedCandidates moveDown:self];
        _currentCandidateIndex++;
        return YES;
    }
    if (keyCode == KEY_ARROW_UP) {
        [sharedCandidates moveUp:self];
        _currentCandidateIndex--;
        return YES;
    }

    // Digit keys 1-9: select prediction by index
    if ([[NSCharacterSet decimalDigitCharacterSet] characterIsMember:ch]) {
        int pressedNumber = characters.intValue;
        if (pressedNumber >= 1 && pressedNumber <= (int)_predictions.count) {
            [self selectPrediction:_predictions[pressedNumber - 1] client:sender];
            return YES;
        }
        // 0 or out of range: exit prediction, type the digit
        [self exitPredictionMode];
        return NO;
    }

    // Delete key: exit prediction mode
    if (keyCode == KEY_DELETE) {
        [self exitPredictionMode];
        return NO;
    }

    // Letter keys: exit prediction mode, start normal typing
    if ((ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z')) {
        [self exitPredictionMode];
        // Re-enter normal typing flow
        [self originalBufferAppend:characters client:sender];
        [sharedCandidates updateCandidates];
        [sharedCandidates show:kIMKLocateCandidatesBelowHint];
        return YES;
    }

    // Punctuation: exit prediction mode, let it pass through
    if ([[NSCharacterSet punctuationCharacterSet] characterIsMember:ch] || [[NSCharacterSet symbolCharacterSet] characterIsMember:ch]) {
        [self exitPredictionMode];
        return NO;
    }

    return NO;
}

- (void)selectPrediction:(NSString *)word client:(id)sender {
    BOOL commitWordWithSpace = [preference boolForKey:@"commitWordWithSpace"];
    NSString *text = word;
    if (commitWordWithSpace) {
        text = [NSString stringWithFormat:@"%@ ", word];
    }

    [sender insertText:text replacementRange:NSMakeRange(NSNotFound, NSNotFound)];

    if (![self isPrivacySensitiveClient:sender]) {
        [self addToContextHistory:word];
    }
    [self exitPredictionMode];

    // Chain: trigger next prediction
    [self triggerNextWordPrediction];
}

#pragma mark - Prediction Mode Management

- (void)exitPredictionMode {
    if (!_predictionMode) return;

    _predictionMode = NO;
    _predictions = nil;
    _currentCandidateIndex = 1;

    [[NextWordPredictor shared] cancelPendingPrediction];

    [sharedCandidates clearSelection];
    [sharedCandidates hide];
    [sharedCandidates setCandidateData:@[]];

    [_annotationWin setAnnotation:@""];
    [_annotationWin hideWindow];
}

- (void)enterPredictionModeWithPredictions:(NSArray<NSString *> *)predictions {
    if (!predictions || predictions.count == 0) return;

    // Don't enter prediction mode if user has already started typing
    if ([self originalBuffer].length > 0) return;

    _predictionMode = YES;
    _predictions = [NSMutableArray arrayWithArray:predictions];
    _currentCandidateIndex = 1;

    [sharedCandidates updateCandidates];
    [sharedCandidates show:kIMKLocateCandidatesBelowHint];
}

#pragma mark - Context History

- (NSMutableArray<NSString *> *)contextHistory {
    if (!_contextHistory) {
        _contextHistory = [NSMutableArray array];
    }
    return _contextHistory;
}

- (BOOL)isPrivacySensitiveClient:(id)client {
    #pragma unused(client)
    return IsSecureEventInputEnabled();
}

- (void)cancelPredictionForPrivacy {
    [self exitPredictionMode];
    [[NextWordPredictor shared] cancelPendingPrediction];
}

- (void)addToContextHistory:(NSString *)word {
    if (!word || word.length == 0) return;
    if ([self isPrivacySensitiveClient:_currentClient]) return;

    // Clean the word (remove trailing spaces, etc.)
    NSString *cleanWord = [word stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (cleanWord.length == 0) return;

    [[self contextHistory] addObject:cleanWord];

    // Keep context history bounded
    while ([self contextHistory].count > kMaxContextHistoryWords) {
        [[self contextHistory] removeObjectAtIndex:0];
    }
}

- (NSString *)contextString {
    return [[self contextHistory] componentsJoinedByString:@" "];
}

#pragma mark - Surrounding Text Context

- (NSString *)surroundingTextContext:(id)client {
    if (!client) return nil;
    if ([self isPrivacySensitiveClient:client]) return nil;

    // Use IMKTextInput protocol to read text before the cursor
    @try {
        NSRange selRange = [client selectedRange];
        if (selRange.location == NSNotFound || selRange.location == 0) return nil;

        // Read up to 500 characters before cursor
        NSUInteger len = MIN(selRange.location, (NSUInteger)500);
        NSRange readRange = NSMakeRange(selRange.location - len, len);
        NSAttributedString *attrStr = [client attributedSubstringFromRange:readRange];
        if (!attrStr || attrStr.length == 0) return nil;

        NSString *raw = attrStr.string;

        // Find the last CJK character and only use text after it.
        // This filters out Chinese/Japanese/Korean text that confuses the LLM.
        NSInteger cutoff = -1;
        for (NSInteger i = (NSInteger)raw.length - 1; i >= 0; i--) {
            unichar ch = [raw characterAtIndex:i];
            BOOL isCJK = (ch >= 0x4E00 && ch <= 0x9FFF) ||  // CJK Unified
                          (ch >= 0x3400 && ch <= 0x4DBF) ||  // CJK Extension A
                          (ch >= 0x3000 && ch <= 0x303F) ||  // CJK Symbols
                          (ch >= 0xFF00 && ch <= 0xFFEF) ||  // Fullwidth forms
                          (ch >= 0x3040 && ch <= 0x30FF);    // Hiragana/Katakana
            if (isCJK) {
                cutoff = i;
                break;
            }
        }

        NSString *context;
        if (cutoff >= 0 && cutoff < (NSInteger)raw.length - 1) {
            context = [[raw substringFromIndex:cutoff + 1] stringByTrimmingCharactersInSet:
                        [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        } else if (cutoff < 0) {
            context = raw;
        } else {
            return nil; // CJK is the very last char
        }

        if (context.length == 0) return nil;

        // Trim to last 500 chars for reasonable context size
        if (context.length > 500) {
            context = [context substringFromIndex:context.length - 500];
            NSRange spaceRange = [context rangeOfString:@" "];
            if (spaceRange.location != NSNotFound && spaceRange.location < 50) {
                context = [context substringFromIndex:spaceRange.location + 1];
            }
        }

        return context;
    } @catch (NSException *e) {
        // Some apps don't support attributedSubstringFromRange
    }
    return nil;
}

#pragma mark - Next Word Prediction Trigger

- (void)triggerNextWordPrediction {
    [self triggerNextWordPredictionWithClient:_currentClient];
}

- (void)triggerNextWordPredictionWithClient:(id)client {
    BOOL enabled = [preference boolForKey:@"enableNextWordPrediction"];
    if (!enabled) return;
    if ([self isPrivacySensitiveClient:client]) {
        [self cancelPredictionForPrivacy];
        return;
    }

    if (![NextWordPredictor shared].isModelLoaded) return;

    // Small delay so the just-committed text is available in the app for surroundingTextContext
    __weak InputController *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(50 * NSEC_PER_MSEC)), dispatch_get_main_queue(), ^{
        InputController *strongSelf = weakSelf;
        if (!strongSelf) return;
        if (strongSelf->_predictionMode) return;
        if ([strongSelf originalBuffer].length > 0) return;
        if ([strongSelf isPrivacySensitiveClient:client]) {
            [strongSelf cancelPredictionForPrivacy];
            return;
        }

        // Build context: prefer surrounding text from the app, fall back to our history
        NSString *context = [strongSelf surroundingTextContext:client];

        if (!context || context.length == 0) {
            context = [strongSelf contextString];
        }
        if (!context || context.length == 0) {
            return;
        }

        [[NextWordPredictor shared] predictNextWords:context
                                               count:kPredictionCount
                                          completion:^(NSArray<NSString *> *predictions) {
                                              InputController *ss = weakSelf;
                                              if (!ss) return;

                                              // Only show predictions if user hasn't started typing
                                              if ([ss originalBuffer].length == 0 && !ss->_predictionMode) {
                                                  [ss enterPredictionModeWithPredictions:predictions];
                                              }
                                          }];
    });
}

#pragma mark - Existing Methods (Modified)

- (BOOL)isMojaveAndLaterSystem {
    NSOperatingSystemVersion version = [NSProcessInfo processInfo].operatingSystemVersion;
    return (version.majorVersion == 10 && version.minorVersion > 13) || version.majorVersion > 10;
}

- (BOOL)deleteBackward:(id)sender {
    NSMutableString *originalText = [self originalBuffer];

    if (_insertionIndex > 0) {
        --_insertionIndex;

        NSString *convertedString = [originalText substringToIndex:originalText.length - 1];

        [self setComposedBuffer:convertedString];
        [self setOriginalBuffer:convertedString];

        [self showPreeditString:convertedString];

        if (convertedString && convertedString.length > 0) {
            [sharedCandidates updateCandidates];
            [sharedCandidates show:kIMKLocateCandidatesBelowHint];
        } else {
            [self reset];
        }
        return YES;
    }
    return NO;
}

- (void)commitComposition:(id)sender {
    NSString *text = [self composedBuffer];

    if (text == nil || text.length == 0) {
        text = [self originalBuffer];
    }

    // Save committed word to context history BEFORE reset
    if (![self isPrivacySensitiveClient:sender]) {
        [self addToContextHistory:text];
    }

    BOOL commitWordWithSpace = [preference boolForKey:@"commitWordWithSpace"];

    if (commitWordWithSpace && text.length > 0) {
        char firstChar = [text characterAtIndex:0];
        char lastChar = [text characterAtIndex:text.length - 1];
        if (![[NSCharacterSet decimalDigitCharacterSet] characterIsMember:firstChar] && lastChar != '\'') {
            text = [NSString stringWithFormat:@"%@ ", text];
        }
    }

    [sender insertText:text replacementRange:NSMakeRange(NSNotFound, NSNotFound)];

    [self reset];

    // Trigger next-word prediction after commit
    [self triggerNextWordPrediction];
}

- (void)commitCompositionWithoutSpace:(id)sender {
    NSString *text = [self composedBuffer];

    if (text == nil || text.length == 0) {
        text = [self originalBuffer];
    }

    // Save committed word to context history BEFORE reset
    if (![self isPrivacySensitiveClient:sender]) {
        [self addToContextHistory:text];
    }

    [sender insertText:text replacementRange:NSMakeRange(NSNotFound, NSNotFound)];

    [self reset];

    // Trigger next-word prediction after commit
    [self triggerNextWordPrediction];
}

- (void)reset {
    [self setComposedBuffer:@""];
    [self setOriginalBuffer:@""];
    _insertionIndex = 0;
    _currentCandidateIndex = 1;
    [sharedCandidates clearSelection];
    [sharedCandidates hide];
    _candidates = [[NSMutableArray alloc] init];
    [sharedCandidates setCandidateData:@[]];
    [_annotationWin setAnnotation:@""];
    [_annotationWin hideWindow];
    // Note: we do NOT reset _predictionMode or _contextHistory here.
    // Prediction mode is managed separately.
}

- (NSMutableString *)composedBuffer {
    if (_composedBuffer == nil) {
        _composedBuffer = [[NSMutableString alloc] init];
    }
    return _composedBuffer;
}

- (void)setComposedBuffer:(NSString *)string {
    NSMutableString *buffer = [self composedBuffer];
    [buffer setString:string];
}

- (NSMutableString *)originalBuffer {
    if (_originalBuffer == nil) {
        _originalBuffer = [[NSMutableString alloc] init];
    }
    return _originalBuffer;
}

- (void)setOriginalBuffer:(NSString *)input {
    NSMutableString *buffer = [self originalBuffer];
    [buffer setString:input];
}

- (void)showPreeditString:(NSString *)input {
    NSDictionary *attrs = [self markForStyle:kTSMHiliteSelectedRawText atRange:NSMakeRange(0, input.length)];
    NSAttributedString *attrString;

    NSString *originalBuff = [NSString stringWithString:[self originalBuffer]];
    if ([input.lowercaseString hasPrefix:originalBuff.lowercaseString]) {
        attrString = [[NSAttributedString alloc]
            initWithString:[NSString stringWithFormat:@"%@%@", originalBuff, [input substringFromIndex:originalBuff.length]]
                attributes:attrs];
    } else {
        attrString = [[NSAttributedString alloc] initWithString:input attributes:attrs];
    }

    [_currentClient setMarkedText:attrString
                   selectionRange:NSMakeRange(input.length, 0)
                 replacementRange:NSMakeRange(NSNotFound, NSNotFound)];
}

- (void)originalBufferAppend:(NSString *)input client:(id)sender {
    NSMutableString *buffer = [self originalBuffer];
    [buffer appendString:input];
    _insertionIndex++;
    [self showPreeditString:buffer];
}

- (void)appendToComposedBuffer:(NSString *)input {
    NSMutableString *buffer = [self composedBuffer];
    [buffer appendString:input];
}

- (NSArray *)candidates:(id)sender {
    // In prediction mode, return predictions as candidates
    if (_predictionMode && _predictions && _predictions.count > 0) {
        _candidates = [NSMutableArray arrayWithArray:_predictions];
        return _predictions;
    }

    // Normal mode: context-aware candidate generation
    NSString *originalInput = [self originalBuffer];

    NSString *context = nil;
    if (![self isPrivacySensitiveClient:_currentClient]) {
        context = [self surroundingTextContext:_currentClient];
        if (!context || context.length == 0) {
            context = [self contextString];
        }
    }
    NSArray *candidateList = [engine getCandidates:originalInput withContext:context];
    _candidates = [NSMutableArray arrayWithArray:candidateList];
    return candidateList;
}

- (void)candidateSelectionChanged:(NSAttributedString *)candidateString {
    if (_predictionMode) {
        // In prediction mode, show annotation for the selected prediction
        BOOL showTranslation = [preference boolForKey:@"showTranslation"];
        if (showTranslation) {
            [self showAnnotation:candidateString];
        }
        return;
    }

    [self _updateComposedBuffer:candidateString];

    [self showPreeditString:candidateString.string];

    _insertionIndex = candidateString.length;

    BOOL showTranslation = [preference boolForKey:@"showTranslation"];
    if (showTranslation) {
        [self showAnnotation:candidateString];
    }
}

- (void)candidateSelected:(NSAttributedString *)candidateString {
    if (_predictionMode) {
        [self selectPrediction:candidateString.string client:_currentClient];
        return;
    }

    [self _updateComposedBuffer:candidateString];

    [self commitComposition:_currentClient];
}

- (void)_updateComposedBuffer:(NSAttributedString *)candidateString {
    [self setComposedBuffer:candidateString.string];
}

- (void)activateServer:(id)sender {
    [sender overrideKeyboardWithKeyboardNamed:@"com.apple.keylayout.US"];

    if (_annotationWin == nil) {
        _annotationWin = [AnnotationWinController sharedController];
    }

    _currentCandidateIndex = 1;
    _candidates = [[NSMutableArray alloc] init];
    _predictionMode = NO;
    _predictions = nil;
}

- (void)deactivateServer:(id)sender {
    [self exitPredictionMode];
    [self reset];
}

- (NSMenu *)menu{
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    return [NSApp.delegate performSelector:NSSelectorFromString(@"menu")];
#pragma clang diagnostic pop
}

- (void)showIMEPreferences:(id)sender {
    [[PreferencesWindowController shared] showWindow];
}

- (void)clickAbout:(NSMenuItem *)sender {
    [self openUrl:@"https://github.com/OMEG-Lu/typeflow"];
}

- (void)openUrl:(NSString *)url {
    NSWorkspace *ws = [NSWorkspace sharedWorkspace];

    NSWorkspaceOpenConfiguration *configuration = [NSWorkspaceOpenConfiguration new];
    configuration.promptsUserIfNeeded = YES;
    configuration.createsNewApplicationInstance = NO;

    [ws openURL:[NSURL URLWithString:url] configuration:configuration completionHandler:^(NSRunningApplication * _Nullable app, NSError * _Nullable error) {
        if (error) {
          NSLog(@"Failed to run the app: %@", error.localizedDescription);
        }
    }];
}

- (void)showAnnotation:(NSAttributedString *)candidateString {
    NSString *annotation = [engine getAnnotation:candidateString.string];
    if (annotation && annotation.length > 0) {
        [_annotationWin setAnnotation:annotation];
        [_annotationWin showWindow:[self calculatePositionOfTranslationWindow]];
    } else {
        [_annotationWin hideWindow];
    }
}

- (NSPoint)calculatePositionOfTranslationWindow {
    // Mac Cocoa ui default coordinate system: left-bottom, origin: (x:0, y:0) ↑→
    // see https://developer.apple.com/library/archive/documentation/General/Conceptual/Devpedia-CocoaApp/CoordinateSystem.html
    // see https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/CocoaDrawingGuide/Transforms/Transforms.html
    // Notice: there is a System bug: candidateFrame.origin always be (0,0), so we can't depending on the origin point.
    NSRect candidateFrame = [sharedCandidates candidateFrame];

    // line-box of current input text: (width:1, height:17)
    NSRect lineRect;
    [_currentClient attributesForCharacterIndex:0 lineHeightRectangle:&lineRect];
    NSPoint cursorPoint = NSMakePoint(NSMinX(lineRect), NSMinY(lineRect));
    NSPoint positionPoint = NSMakePoint(NSMinX(lineRect), NSMinY(lineRect));
    positionPoint.x = positionPoint.x + candidateFrame.size.width;
    NSScreen *currentScreen = [NSScreen currentScreenForMouseLocation];
    NSPoint currentPoint = [currentScreen convertPointToScreenCoordinates:cursorPoint];
    NSRect rect = currentScreen.frame;
    int screenWidth = (int)rect.size.width;
    int marginToCandidateFrame = 20;
    int annotationWindowWidth = _annotationWin.width + marginToCandidateFrame;
    int lineHeight = lineRect.size.height; // 17px

    if (screenWidth - currentPoint.x >= candidateFrame.size.width) {
        // safe distance to display candidateFrame at current cursor's left-side.
        if (screenWidth - currentPoint.x < candidateFrame.size.width + annotationWindowWidth) {
            positionPoint.x = positionPoint.x - candidateFrame.size.width - annotationWindowWidth;
        }
    } else {
        // assume candidateFrame will display at current cursor's right-side.
        positionPoint.x = screenWidth - candidateFrame.size.width - annotationWindowWidth;
    }
    if (currentPoint.y >= candidateFrame.size.height) {
        positionPoint.y = positionPoint.y - 8; // Both 8 and 3 are magic numbers to adjust the position
    } else {
        positionPoint.y = positionPoint.y + candidateFrame.size.height + lineHeight + 3;
    }

    return positionPoint;
}

@end
