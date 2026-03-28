# Next Word Prediction Feature

## Overview

This feature adds LLM-powered next-word prediction to Typeflow. After you commit a word, the input method uses a local language model to predict the next word you might type, similar to smartphone keyboard suggestions.

## How It Works

1. You type and select a word normally (e.g., "hello")
2. After the word is committed, the LLM analyzes your recent context
3. 5-6 predicted next words appear in the candidate panel (e.g., "world", "there", "everyone")
4. You can:
   - **Select a prediction** by pressing its number (1-6) or Space (selects first)
   - **Ignore and type normally** — just start typing and predictions disappear
   - **Dismiss** with ESC
5. Selecting a prediction chains into the next prediction cycle

## Model Tiers

Three model sizes are available. Choose based on your hardware and preference:

| Tier | Model | Parameters | GGUF Size | Speed | Quality |
|------|-------|-----------|-----------|-------|---------|
| **Small** | SmolLM-135M | ~135M | ~100MB | Fastest (~10ms) | Basic |
| **Medium** | Qwen2-0.5B | ~0.5B | ~350MB | Fast (~30ms) | Good |
| **Large** | Qwen2-1.5B | ~1.5B | ~1GB | Moderate (~80ms) | Best |

All models run 100% locally via llama.cpp with Metal (GPU) acceleration on Apple Silicon.

> **Note:** If the large model introduces noticeable delay on your machine, switch to Medium or Small in Preferences.

## Setup

### Prerequisites

- macOS 13.5.2+
- Xcode with command line tools
- CMake (`brew install cmake`)
- ~2GB disk space (for all models) or ~200MB (small model only)

### Step 1: Build llama.cpp and Download Models

```bash
# Build llama.cpp + download small model (default)
./scripts/setup-llama.sh

# Or download all models
./scripts/setup-llama.sh --all

# Or download a specific model tier
./scripts/setup-llama.sh --model medium

# Check status
./scripts/setup-llama.sh --status
```

### Step 2: Configure Xcode Project

After running the setup script, add the following to the Xcode project:

#### Add Static Libraries

1. Open `hallelujah.xcworkspace` in Xcode
2. Select the `Typeflow` target → Build Phases → Link Binary With Libraries
3. Add all `.a` files from the `lib/` directory:
   - `libllama.a`
   - `libggml.a`
   - `libggml-base.a`
   - `libggml-metal.a`
   - `libggml-cpu.a`
   - (and any other `libggml-*.a` files)
4. Also add these system frameworks:
   - `Metal.framework`
   - `MetalKit.framework`
   - `Accelerate.framework` (if not already linked)

#### Add Header Search Path

1. Target → Build Settings → Header Search Paths
2. Add: `$(SRCROOT)/include/llama` (recursive)

#### Add Source File

1. Add `src/NextWordPredictor.mm` to the Typeflow target

#### Add Metal Shader

If llama.cpp was built with Metal support, you need to include the Metal shader:

1. Find `ggml-metal.metal` in `third_party/llama.cpp/ggml/src/`
2. Add it to the project as a resource (Copy Bundle Resources)

### Step 3: Build and Install

```bash
./build.sh
```

## Configuration

Open Preferences (`http://localhost:62718/index.html`) to:

- **Enable/Disable** next-word prediction
- **Choose model tier** (Small / Medium / Large)

Settings take effect immediately. Changing the model tier triggers an async model reload.

## Model Storage

Models are stored in:
```
~/Library/Application Support/Typeflow/models/
```

Expected files:
- `smollm-135m-q8_0.gguf` (Small)
- `qwen2-0.5b-q8_0.gguf` (Medium)
- `qwen2-1.5b-q4_k_m.gguf` (Large)

## Architecture

### New Files

- `src/NextWordPredictor.h` — Predictor interface
- `src/NextWordPredictor.mm` — llama.cpp integration (model loading, tokenization, inference, top-k sampling)
- `scripts/setup-llama.sh` — Build and model download automation

### Modified Files

- `src/InputController.h` — Added prediction mode state variables
- `src/InputController.mm` — Prediction mode lifecycle, context tracking, candidate display
- `src/main.mm` — Predictor initialization, new preference defaults
- `src/WebServer.m` — New preference endpoints and model status API
- `web/index.html` — Model tier selector UI
- `web/index.js` — Prediction preference handling
- `web/index.css` — Prediction settings styles

### Data Flow

```
User commits word
    → addToContextHistory()
    → triggerNextWordPrediction()
    → NextWordPredictor.predictNextWords() [async, background queue]
        → llama_tokenize() → llama_decode() → top-k sampling
    → enterPredictionModeWithPredictions() [main queue callback]
    → IMKCandidates shows predicted words
    → User selects or starts typing
```

### Key Design Decisions

1. **Async inference**: All LLM inference runs on a dedicated serial dispatch queue to never block the UI thread.
2. **Cancellation**: Starting to type immediately cancels any pending prediction, ensuring zero latency impact on normal typing.
3. **Context window**: Last 50 words are maintained as context for better prediction quality.
4. **Word-boundary filtering**: Only tokens that represent complete words (alphabetic, word-boundary tokens) are returned as predictions.
5. **Metal GPU acceleration**: llama.cpp uses Metal by default on macOS for fast inference on Apple Silicon.
