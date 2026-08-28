# Platform style contract

The publisher bridge does not create one generic post format. It receives a platform-neutral T1/T2 package plus the central Publish Style adapter result. Each platform adapter supplies only the fields actually supported by that platform and returns field/readback evidence. Unsupported fields are ignored rather than forced through DOM automation. Final live publication remains gated until the platform-specific formatter and no-publish editor test both pass.
