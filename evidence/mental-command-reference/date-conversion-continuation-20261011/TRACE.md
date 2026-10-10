# Installed date conversion reference

Cortex metadata calls Qt DateFormat9 for import and export. Its datetime2String helper checks isValid, obtains offsetFromUtc, constructs QTimeZone(int), sets that timezone with TransitionResolution1, then toString(format9). Actual Cortex body was captured in metadata-schema-continuation-20261011/conversion-symbols.txt. This continuation captures the installed QtCore fromString/toString/toBool bodies. The installed framework reports6.8.3; identity/hash is recorded in qt-identity.txt. No framework or vendor assets are copied into the product.

Official matching source consulted: https://github.com/qt/qtbase/blob/v6.8.3/src/corelib/time/qdatetime.cpp and qdatetime.h, plus src/corelib/text/qstringview.h. Sources were read in /tmp, not bundled. Qt documentation: https://doc.qt.io/qt-6.8/qdatetime.html . Implementation uses our own bounded Swift parser and Gregorian day calculations; it does not link Qt.

A read-only standalone C++ probe calls the installed Qt library, reproducing the exact helper call sequence. Its minimal ABI declarations follow official header sizes/layout and inspected arm64 bodies: QStringView16bytes, QString24bytes, QDateTime8bytes, QTimeZone8bytes. Oracle probe source is retained for reproduction. QString returned allocations deliberately remain alive until this short-lived process exits; it is a comparison tool, not a reusable product allocation implementation. Library string layout is a version/architecture dependency. The probe does not run Cortex or query any headset/account/profile. Input strings are independent synthetic vectors.

Observed helper behavior: valid UTC becomes explicit +00:00 after fixed-offset conversion; fractions round to three milliseconds and may carry to the following day;24:00 becomes next-day midnight; invalid calendar/leap-second values emit no metadata date. QTimeZone(int) rejects offsets beyond±16h even though the lexical offset parser permits hours through23. At9999end-year rollover, Qt can have a valid internal date whose ISO formatter emits empty; the Swift supported domain emits the same empty wire result.

ReferenceDateMetadata covers ASCII yyyy-MM-dd, T/t/space, fullHH:mm:ss, optional dot/comma fraction1..9digits, explicitZ/z or ±HH[:mm]/±HHmm. Resource cap64bytes is our policy. Numeric bounds, calendar validity and fixed-offset bounds return empty for invalid supported inputs. Unrecognized syntax, local timezone/no-zone values, partial hour/minute forms and >9fractiondigits throw unsupportedSyntax; they are NOT silently mapped to invalid. Qt accepts additional forms not implemented here. DST/local timezone interpretation is explicitly not claimed. Raw ReferenceTrainingMetadata/ProfileStore wire values remain unchanged; normalization is opt-in comparison only.

Validation: nineteen hand-inspected valid and eight invalid installed-oracle vectors; deterministic random matrix160synthetic explicit-zone inputs generated with Python Random(611), covering leap/century dates, midnight, fractional rounding, offset endpoints and invalid24hour/minute combinations. Swift test reads retained TSV outputs and compares all rows. No guessed model parameters or physiological assertions. No vendor assets needed.

Reproduce oracle on M4:

```sh
clang++ -std=c++17 oracle-probe.cpp -F"/Applications/EmotivApps/EMOTIV Launcher.app/Contents/Frameworks" -framework QtCore -Wl,-rpath,"/Applications/EmotivApps/EMOTIV Launcher.app/Contents/Frameworks" -o /tmp/eeg-date-probe
TZ=UTC /tmp/eeg-date-probe < input-cases.txt
```

Reproduce independent test: swift test --package-path apple --filter ReferenceDateMetadataTests. Core independent storage/acquisition has no Qt runtime dependency.
