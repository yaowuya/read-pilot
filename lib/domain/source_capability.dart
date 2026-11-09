/// Source features that may require a runtime implementation or user grant.
enum SourceCapability {
  staticHeaders,
  javascript,
  login,
  cookieJar,
  explore,
  xpath,
  jsonPath,
  regex,
  contentPagination,
  audio,
  image,
  download,
  video,
}

/// The current implementation and permission set for one platform runtime.
class SourceRuntimeProfile {
  const SourceRuntimeProfile({
    required this.name,
    this.implemented = const {},
    this.permitted = const {},
  });

  final String name;
  final Set<SourceCapability> implemented;
  final Set<SourceCapability> permitted;

  /// Capabilities whose support is decided per-rule via
  /// [SourceCapabilityRequirement.implementedProfiles], not the profile set
  /// alone (unsafe XPath / catastrophic regex / unrestricted JS stay blocked).
  static const profileGated = {
    SourceCapability.xpath,
    SourceCapability.regex,
    SourceCapability.javascript,
  };

  static const nativeCore = SourceRuntimeProfile(
    name: 'native-core',
    implemented: {
      SourceCapability.staticHeaders,
      SourceCapability.explore,
      SourceCapability.jsonPath,
      SourceCapability.contentPagination,
      SourceCapability.xpath,
      SourceCapability.regex,
    },
    permitted: {
      SourceCapability.staticHeaders,
      SourceCapability.explore,
      SourceCapability.jsonPath,
      SourceCapability.contentPagination,
      SourceCapability.xpath,
      SourceCapability.regex,
    },
  );
  static const androidCore = SourceRuntimeProfile(
    name: 'android-core',
    implemented: {
      SourceCapability.staticHeaders,
      SourceCapability.explore,
      SourceCapability.jsonPath,
      SourceCapability.contentPagination,
      SourceCapability.xpath,
      SourceCapability.regex,
      SourceCapability.javascript,
    },
    permitted: {
      SourceCapability.staticHeaders,
      SourceCapability.explore,
      SourceCapability.jsonPath,
      SourceCapability.contentPagination,
      SourceCapability.xpath,
      SourceCapability.regex,
      SourceCapability.javascript,
    },
  );
  static const webCore = SourceRuntimeProfile(
    name: 'web-core',
    implemented: {
      SourceCapability.explore,
      SourceCapability.jsonPath,
      SourceCapability.contentPagination,
      SourceCapability.xpath,
      SourceCapability.regex,
    },
    permitted: {
      SourceCapability.explore,
      SourceCapability.jsonPath,
      SourceCapability.contentPagination,
      SourceCapability.xpath,
      SourceCapability.regex,
    },
  );
}

/// A field-level requirement discovered without executing imported content.
class SourceCapabilityRequirement {
  const SourceCapabilityRequirement({
    required this.path,
    required this.capability,
    required this.message,
    this.implementedProfiles = const {},
    this.permittedProfiles = const {},
  });

  final String path;
  final SourceCapability capability;
  final String message;
  final Set<String> implementedProfiles;
  final Set<String> permittedProfiles;
}

/// One compatibility issue exposed to import previews and diagnostics.
class SourceCapabilityDiagnostic {
  const SourceCapabilityDiagnostic({
    required this.path,
    required this.capability,
    required this.message,
    required this.runtimeImplemented,
    required this.platformPermitted,
  });

  final String path;
  final SourceCapability capability;
  final String message;
  final bool runtimeImplemented;
  final bool platformPermitted;
}

/// Compatibility status keeps format, runtime and platform claims independent.
class SourceCapabilityReport {
  SourceCapabilityReport({
    required this.profile,
    required Iterable<SourceCapabilityRequirement> requirements,
  }) : diagnostics = List.unmodifiable(
         requirements.map(
           (requirement) => SourceCapabilityDiagnostic(
             path: requirement.path,
             capability: requirement.capability,
             message: requirement.message,
             runtimeImplemented: _runtimeImplemented(profile, requirement),
             platformPermitted: _platformPermitted(profile, requirement),
           ),
         ),
       );

  final SourceRuntimeProfile profile;
  final List<SourceCapabilityDiagnostic> diagnostics;

  bool get formatAccepted => true;
  bool get runtimeImplemented =>
      diagnostics.every((diagnostic) => diagnostic.runtimeImplemented);
  bool get platformPermitted =>
      diagnostics.every((diagnostic) => diagnostic.platformPermitted);

  static bool _runtimeImplemented(
    SourceRuntimeProfile profile,
    SourceCapabilityRequirement requirement,
  ) {
    if (SourceRuntimeProfile.profileGated.contains(requirement.capability)) {
      return requirement.implementedProfiles.contains(profile.name);
    }
    return profile.implemented.contains(requirement.capability) ||
        requirement.implementedProfiles.contains(profile.name);
  }

  static bool _platformPermitted(
    SourceRuntimeProfile profile,
    SourceCapabilityRequirement requirement,
  ) {
    if (SourceRuntimeProfile.profileGated.contains(requirement.capability)) {
      return requirement.permittedProfiles.contains(profile.name);
    }
    return profile.permitted.contains(requirement.capability) ||
        requirement.permittedProfiles.contains(profile.name);
  }
}
