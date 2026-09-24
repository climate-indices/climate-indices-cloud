# SPI is published with Pearson III on a fixed 1895–2022 calibration window

The compute library measured its SPI reference ceilings against NOAA NCEI's climate-divisional
SPI for exactly one configuration: the Pearson Type III distribution, calibrated on 1895–2022,
across all 344 divisions (`tests/fixture/ncei_spi/provenance.json` in the library). For SPI-3
those ceilings are 0.03 (median), 0.06 (p90), and 1.4 (max) absolute SPI difference, against
measured values of 0.0126, 0.0287, and 0.8376. [ADR-0002](0002-validation-as-a-publishing-gate.md)
says a dataset with no recorded ceiling cannot ship, so this is the only SPI configuration the
Validation Gate can currently enforce. The service therefore publishes SPI with Pearson III and
a fixed calibration window of 1895–2022, and the published path carries it
(`published/spi/3/cal1895-2022/`, per [ADR-0001](0001-two-layouts-for-published-data.md)).
This is not the climatological convention. The WMO normal is 1991–2020, and NCEI documents a
1931–1990 window; neither has a measured ceiling here.

## Considered options

**Gamma on the 1991–2020 WMO normal.** The convention most users expect, and a 30-year window
meets the library's minimum. Rejected because the library has measured no reference ceiling for
it, so the gate could not block a bad publish and ADR-0002 forbids shipping it. Adopting it
means first measuring a ceiling in the library.

**NCEI's documented 1931–1990 window.** The brief's assumption. Rejected because the library
found that window "disagrees badly" with NCEI's actual values, and NCEI's real behavior is a
full period-of-record calibration (Baldwin & Chen 2020). Matching the documentation would mean
disagreeing with the product it is checked against.

**An expanding period-of-record window, as NCEI does.** Closest to NCEI's actual numbers.
Rejected because the window's end would move with every new month, so each month would be a
different product, and the calibration-window path and the Published Dataset identity would
churn monthly.

## Consequences

- SPI stays `characterization-only`. A fixed 1895–2022 window does not upgrade the evidence
  class; that is a separate, publishable piece of work (ADR-0002).
- Changing the SPI configuration requires a ceiling measured for it in the library first. A
  different calibration window is a different Published Dataset that can coexist beside this
  one, not a revision of it.
- The reference comparison is limited to 1895–2022 and reads the library's committed fixture
  at the pinned engine tag. NCEI's live file follows a full-record calibration, so values for a
  fixed historical month shift as its record grows; comparing against a fresh download would
  breach ceilings that were measured against the fixture.
- Months after 2022 are computed and published against the 1895–2022 window but have no
  reference to be checked against; the gate covers them only with its coverage, units, and
  calendar checks.
