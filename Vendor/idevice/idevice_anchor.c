/*
 * Anchor translation unit for the SwiftPM `idevice` C target.
 *
 * SPDX-License-Identifier: MIT
 * Copyright 2026 Jackson Coxson (idevice, https://github.com/jkcoxson/idevice)
 * Copyright (C) 2026 haruki0420 and contributors (this anchor file)
 *
 * The target only ships headers: `idevice.h` (vendored from TLocation, which
 * vendors it from jkcoxson/idevice, MIT — see Vendor/idevice/LICENSE) and
 * `module.modulemap`. SwiftPM requires a C target to contain at least one
 * compilable source file, so this file exists purely to satisfy that
 * requirement. It deliberately does not include `idevice.h`: the header is
 * parsed through the module map when Swift imports the `idevice` module,
 * exactly like TLocation's Xcode target.
 *
 * `idevice.h` also embeds declarations derived from libplist (LGPL-2.1); see
 * NOTICE for the attribution.
 *
 * The static library `libidevice_ffi.a` is fetched by `scripts/fetch-vendor.sh`
 * and linked through the `linkerSettings` declared in `Package.swift`.
 */

#include <stdint.h>

void p2pgps_idevice_link_anchor(void);
void p2pgps_idevice_link_anchor(void) {
    /* no-op */
}
