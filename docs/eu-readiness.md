# EU readiness — requirements and release gates

Reviewed 2026-09-17. Status: NOT compliance-certified or launch-approved.
This is an engineering and operational gap assessment, not a legal opinion.
The founder reports being in Denmark. Use Denmark as the provisional establishment
assumption, not confirmation of the company's legal establishment. Launch markets,
legal entity and intended professional uses remain to be confirmed.

## Denmark-specific scope

- Review GDPR together with Denmark's supplementary Data Protection Act
  (Databeskyttelsesloven). Datatilsynet is the Danish data protection authority:
  [official guidance](https://www.datatilsynet.dk/english) and
  [small-business guidance](https://www.datatilsynet.dk/regler-og-vejledning/gdpr-univers-for-smaa-virksomheder).
- Digitaliseringsstyrelsen is the nationally coordinating AI Act supervisory
  authority; do not assume it is the sole competent authority for every obligation:
  [official AI supervision page](https://digst.dk/tilsyn/ai-forordningen/).
- Confirm establishment and processing roles before identifying the competent/lead
  authority for cross-border processing. Founder residence alone is insufficient.
- Review Danish recording, workplace and confidentiality rules before expanding
  beyond personal user-initiated dictation. Launch markets may add other local rules.
- Keep English-first recognition unchanged: a Danish business base does not by
  itself change the supported dictation language or require Danish-only hosting.

## Scope and responsibility

English, user-initiated on-device dictation; no identification, emotion inference,
training on user content, accounts, advertising, cloud sync or meeting recording.
Offline processing is a minimisation strategy, not a blanket GDPR exemption.
Map responsibilities per processing activity: selling a local tool does not alone
make the vendor the controller/processor of all documents dictated by its users.
The company may separately be controller for support, website visitors and research
participants. Business customers may control their employees' processing. Record
these distinctions and any processor relationships instead of using a generic DPA.

Voice and transcripts can identify people and contain sensitive information.
Do not treat every voice recording as special-category biometric identification;
that depends on the processing purpose. Health and other sensitive content require
separate legal analysis where the company processes it.

## Observed code gaps — must be resolved or explicitly scoped before release

- Native transcription writes a temporary WAV, removed on ordinary completion
  but not reliably after crashes. Prefer memory streaming; until then implement
  scoped crash recovery, permissions and tested retention limits.
- History uses AES-GCM/Keychain, but dictionaryTerms remains in UserDefaults.
  Encrypt sensitive dictionary content with reversible migration and test recovery.
- Coordinator suppresses history deletion failures and can clear the UI despite
  persistence failure. Report failures; verify deletion after reopening the store.
- Review store load/key failure paths: corrupted or inaccessible encrypted data
  must not be silently replaced with an empty store. Add failure/recovery tests.
- History is saved automatically. Add a no-history default for new users and
  explicit save/retention choices; do not delete existing users' records implicitly.
- Focus capture reads field contents before any client-side bound. Disable optional
  context by default; bound it near the cursor before passing it to an engine.
- Clipboard restoration exists, but cannot retract data observed by another app
  or copied through Universal Clipboard. Explain this boundary and offer strict
  no-clipboard fallback. Never promise deletion from destination applications.
- No demonstrated full network audit, portable export, retention expiry, or
  comprehensive local-data deletion workflow. OS backups require separate disclosure.

## Engineering acceptance

1. Explicit microphone initiation/indicator, tested cancellation and secure-field
   blocking; no continuous background microphone. No prerecorded playback needed
   for code/security tests.
2. No audio/transcript/context in telemetry, logs, crash attachments, URLs or download
   requests. Optional diagnostics are previewable/redacted and off by default.
3. Model downloads contain no dictated content; disclose the host receiving network
   metadata such as IP addresses. Audit third-party SDK/system-service behavior.
4. Cold and warm offline runs, packet inspection and denial of external networking
   demonstrate no content egress. OS-managed asset storage is reported separately.
5. Test local export, corrections, individual/all deletion, retention expiry,
   cancelled/error/crashed sessions, dictionary and backup behavior. Rights only
   apply as legally appropriate; do not collect remote copies merely to offer export.
6. Signed releases, dependency/license inventory, pinned verified assets, update
   security and vulnerability handling. Do not equate ad-hoc signing with release security.

## Governance and applicable-law review

- GDPR: data map, purposes, lawful basis per activity, minimisation, retention,
  privacy notice, rights handling, security and breach response. OS microphone
  permission is not automatically valid consent for every processing purpose.
  Screen whether a DPIA and DPO are required; do not assume either is universally
  mandatory or unnecessary for a small company.
- Research: audio copyright/licensing and GDPR lawful processing are separate.
  Verify corpus rights, provenance, notices and speaker protections. Voice samples
  labelled with speaker IDs are generally pseudonymous, not necessarily anonymous.
  Submission to Flow for benchmarking is a separate disclosure/recipient decision;
  dataset download permission alone does not authorize it.
- Vendors/transfers: assess processors and contracts where applicable, hosting and
  support access, and any non-EEA transfers. EU hosting alone is not compliance;
  GDPR does not impose universal EU-only hosting.
- ePrivacy and national law: assess device storage/access and nonessential analytics
  before introducing SDKs or trackers. Recording, employment and confidentiality
  rules vary by country. Keep meeting/third-party recording outside current scope.
- AI Act: document intended use and provider role. Ordinary dictation is not
  automatically high-risk; a change to medical, employment or biometric decisions
  requires reassessment. Explain AI transcription/cleanup and possible errors.
  Assess Article 50; standard editing/non-substantial semantic alteration may be
  excepted from output marking, but do not assume all future generative rewriting
  is exempt. Address applicable staff AI-literacy duties.
- Cyber Resilience Act: assess commercial software scope and economic-operator
  duties before EU distribution. Reporting duties started 11 September 2026;
  main requirements apply 11 December 2027. Track vulnerability/incident reporting,
  secure development, support lifetime and conformity obligations if applicable.
- Distribution: separately screen consumer/digital-content obligations, applicable
  accessibility rules, national language requirements and Apple privacy declarations.
  No generic claim of compliance with every EU law is permitted.

## Release gate

Maintain a requirement → implementation → test-evidence register. Resolve the
engineering gaps, complete operational documents and get qualified country-specific
review before a public compliance claim. Current priority: privacy/storage fixes,
then native-model integration, then device and competitive evaluation. No money
is spent by maintaining this checklist; later legal/distribution costs need a decision.

## Official sources

- [EDPB privacy by design/default](https://www.edpb.europa.eu/topics/ai-and-technology/privacy-by-design-and-by-default_en)
- [EDPB lawful processing](https://www.edpb.europa.eu/sme/be-compliant/process-personal-data-lawfully_en)
- [EDPB individual rights](https://www.edpb.europa.eu/sme/be-compliant/respect-individuals-rights_en)
- [EDPB security](https://www.edpb.europa.eu/sme/be-compliant/secure-personal-data_en)
- [EDPB compliance/DPIA/DPO guidance](https://www.edpb.europa.eu/sme/be-compliant/be-compliant_en)
- [EDPB voice-assistant guidance](https://www.edpb.europa.eu/system/files/2021-07/edpb_guidelines_202102_on_vva_v2.0_adopted_en.pdf)
- [Commission AI Act overview](https://digital-strategy.ec.europa.eu/en/policies/regulatory-framework-ai)
- [Commission Article 50 FAQ](https://digital-strategy.ec.europa.eu/en/faqs/transparency-obligations-under-article-50-ai-act)
- [Commission Cyber Resilience Act](https://digital-strategy.ec.europa.eu/en/policies/cyber-resilience-act)
- [EDPB ePrivacy technical-scope guidance](https://www.edpb.europa.eu/system/files/2023-11/edpb_guidelines_202302_technical_scope_art_53_eprivacydirective_en.pdf)
