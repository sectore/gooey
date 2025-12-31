//! Animation System
//!
//! Time-based interpolation for smooth UI transitions.
//!
//! - `Animation` (AnimationConfig) - Configuration for animation timing
//! - `AnimationHandle` - Current state of an animation (progress, running, etc.)
//! - `AnimationState` - Internal state tracking
//! - `Easing` - Easing functions (linear, easeIn, easeOut, etc.)
//! - `Duration` - Time duration type
//! - `lerp`, `lerpInt`, `lerpColor` - Interpolation helpers

const std = @import("std");

// =============================================================================
// Animation Module
// =============================================================================

pub const animation = @import("animation.zig");

// =============================================================================
// Core Types
// =============================================================================

pub const AnimationConfig = animation.AnimationConfig;
pub const Animation = AnimationConfig; // Alias for convenience
pub const AnimationHandle = animation.AnimationHandle;
pub const AnimationState = animation.AnimationState;
pub const AnimationId = animation.AnimationId;

// =============================================================================
// Timing
// =============================================================================

pub const Duration = animation.Duration;
pub const Easing = animation.Easing;
pub const EasingFn = animation.EasingFn;

// =============================================================================
// Interpolation Helpers
// =============================================================================

pub const lerp = animation.lerp;
pub const lerpInt = animation.lerpInt;
pub const lerpColor = animation.lerpColor;

// =============================================================================
// Internal
// =============================================================================

pub const calculateProgress = animation.calculateProgress;
pub const hashString = animation.hashString;
pub const computeTriggerHash = animation.computeTriggerHash;

// =============================================================================
// Tests
// =============================================================================

test {
    std.testing.refAllDecls(@This());
}
