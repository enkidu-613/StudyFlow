# Chinese AI Coach Chat Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the one-shot English diagnostic card with a Chinese multi-turn AI study-coach conversation.

**Architecture:** The page retains a bounded in-memory chat history for its lifetime. Each request combines that history with a fresh local study-data summary, then sends it to the user's existing OpenAI-compatible endpoint using a Chinese system prompt. Replies are advice only; they cannot mutate tasks or schedule blocks.

**Tech Stack:** Flutter/Dart, existing OpenAI-compatible HTTP client, flutter_test.

## Global Constraints

- Reuse the AI Base URL, model and API key already stored in device secure storage.
- Send no credentials to the StudyFlow server; the provider request remains client-to-provider.
- Produce simplified Chinese coaching replies and keep raw diagnostic reason codes out of the UI.
- Keep conversation history only while this page is open; do not add a database migration in this slice.

---

### Task 1: Add a Chinese conversational AI request contract

**Files:**
- Modify: `apps/client/lib/features/ai/ai_repository.dart`
- Modify: `apps/client/lib/features/ai/today_ai_planning.dart`
- Modify: `apps/client/test/features/ai/today_ai_planning_test.dart`

- [x] Write a failing test asserting that a user message and earlier chat turns reach the repository alongside current local study context.
- [x] Run the test and confirm the conversational planning API is missing.
- [x] Add `AiCoachMessage`, `AiCoachReply`, a repository chat request, and a Chinese system prompt that requests natural-language advice.
- [x] Run the focused planner test and confirm it passes.

### Task 2: Replace the recommendation card with a chat page

**Files:**
- Modify: `apps/client/lib/features/ai/recommendation_screen.dart`
- Modify: `apps/client/lib/main.dart`
- Modify: `apps/client/test/features/ai/recommendation_screen_test.dart`

- [x] Write a failing widget test for sending a Chinese message and rendering the Chinese AI reply as chat bubbles.
- [x] Run the widget test and confirm the old one-shot request UI cannot satisfy it.
- [x] Implement the conversation list, input composer, loading state and safe error state; connect it to the planning request in the router.
- [x] Run the focused widget test and confirm it passes.

### Task 3: Regression verification

- [x] Run `mise exec -- flutter analyze` in `apps/client`.
- [x] Run `mise exec -- flutter test` in `apps/client`.
