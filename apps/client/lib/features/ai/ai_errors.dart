/// Uniform, user-visible AI failures across all provider protocols.
sealed class AiApiFailure implements Exception {
  const AiApiFailure(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() {
    final causeText = cause == null ? '' : ' (cause: $cause)';
    return '$message$causeText';
  }
}

/// HTTP 401/403: the provider rejected the configured API key.
final class AiAuthenticationFailure extends AiApiFailure {
  const AiAuthenticationFailure(super.message, {super.cause});
}

/// DNS, connection reset, TLS, or timeout before an HTTP response arrived.
final class AiNetworkFailure extends AiApiFailure {
  const AiNetworkFailure(super.message, {super.cause});
}

/// The provider returned a response that does not match the selected
/// protocol's contract.
final class AiSchemaFailure extends AiApiFailure {
  const AiSchemaFailure(super.message, {super.cause});
}

/// HTTP 429: rate limit or quota exceeded.
final class AiRateLimitFailure extends AiApiFailure {
  const AiRateLimitFailure(super.message, {super.cause});
}

/// HTTP 5xx: the provider is temporarily unavailable.
final class AiProviderUnavailableFailure extends AiApiFailure {
  const AiProviderUnavailableFailure(super.message, {super.cause});
}

/// The model or provider cannot perform the requested tool work.
final class AiCapabilityFailure extends AiApiFailure {
  const AiCapabilityFailure(super.message, {super.cause});
}
