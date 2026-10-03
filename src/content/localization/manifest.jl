const EnUsLocales = LocalizedContent.LocaleDeclaration[
    LocalizedContent.LocaleDeclaration("en-US", true),
]

const EnUsMessages = LocalizedContent.UiMessageDeclaration[
    source.message for source in UiMessageSources
]

const EnUsTranslations = LocalizedContent.UiTranslationDeclaration[
    LocalizedContent.UiTranslationDeclaration(
        "en-US", source.message.key, source.en_us_template)
    for source in UiMessageSources
]

const ContentSubjects = vcat(
    LocalizedContent.ContentSubjectDeclaration[
        LocalizedContent.ContentSubjectDeclaration("builtin", descriptor.id)
        for descriptor in AnimationDescriptors],
    LocalizedContent.ContentSubjectDeclaration[
        LocalizedContent.ContentSubjectDeclaration("builtin", UUID(UInt128(0)))])

const EnUsAvailability = LocalizedContent.AvailabilityDeclaration[
    LocalizedContent.AvailabilityDeclaration(
        "builtin", assignment.first, "en-US", assignment.second, true)
    for assignment in EnUsEditionAssignments
]

const AuthoredManifest = LocalizedContent.ContentManifest(
    EnUsLocales,
    EnUsMessages,
    EnUsTranslations,
    EnUsCatalogNames,
    ContentSubjects,
    EditionDeclarations,
    EnUsAvailability)

LocalizedContent.validate_content_manifest(AuthoredManifest, AnimationDescriptors)
