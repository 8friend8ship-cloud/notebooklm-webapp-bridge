# No-publish platform tests

Each supported platform must pass twice before the first live-publication approval:
- page/site match
- existing login/session detectable without credential capture
- editor/uploader/composer control detected
- draft/sentinel text can be filled when safe
- filled value is read back
- sentinel is cleared/restored
- no publish/upload/generate button is clicked
- result is written to central QA/run log

For upload-only surfaces where draft text cannot be safely inserted, the equivalent no-publish UI/field detection and readback gate is used.
