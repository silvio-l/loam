part of 'part_ref_host.dart';

/// A class declared in the part file that references PartRefProvider.usedViaPartFile.
///
/// This reference must be visible to the UsageIndex even though this file is a
/// part file (not a standalone library). If UsageIndex only visits standalone
/// resolved entries, this reference is invisible and PartRefProvider.usedViaPartFile
/// is incorrectly reported as unused (False Positive, HellerIO FP #2 pattern).
class PartRefImpl {
  static String getRef() => PartRefProvider.usedViaPartFile;
}
