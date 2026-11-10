# Changelog

## [0.2.3](https://github.com/m9tdev/OpenDisplay/compare/v0.2.2...v0.2.3) (2026-11-10)


### Bug Fixes

* apply resolution and refresh rate only when the slider is released ([#19](https://github.com/m9tdev/OpenDisplay/issues/19)) ([f4690bc](https://github.com/m9tdev/OpenDisplay/commit/f4690bc7e6edd6ff3e6392d0ee2a1fd2bb14bfff))
* clear a stale "Could not turn on" error once a display is on again ([#7](https://github.com/m9tdev/OpenDisplay/issues/7)) ([6f6d39b](https://github.com/m9tdev/OpenDisplay/commit/6f6d39b2541f02fb1861c79a706e93f5d3636c6b))
* give twin monitors without a serial number their own settings ([#17](https://github.com/m9tdev/OpenDisplay/issues/17)) ([0eae739](https://github.com/m9tdev/OpenDisplay/commit/0eae739822d8efb9fea8f47be232fb64a8062b20))
* keep dimming and brightness sync when a display reconnects ([#8](https://github.com/m9tdev/OpenDisplay/issues/8)) ([02db751](https://github.com/m9tdev/OpenDisplay/commit/02db751e8b58ae37a3de9be428aebe94bb7ad526))
* keep the brightness, volume and mute the app shows in step with the monitor ([#16](https://github.com/m9tdev/OpenDisplay/issues/16)) ([4267b99](https://github.com/m9tdev/OpenDisplay/commit/4267b9932e2a0df67b76b914ded9999bc19a4687))
* keep the menu open during a slider drag and clear a fixed Launch at Login error ([#15](https://github.com/m9tdev/OpenDisplay/issues/15)) ([2b87ffa](https://github.com/m9tdev/OpenDisplay/commit/2b87ffa974cca9c57fa6962e93bd35d2a85eec3c))
* keep what waits for the built-in display when a calibration ends with it off ([#27](https://github.com/m9tdev/OpenDisplay/issues/27)) ([4ea3f6d](https://github.com/m9tdev/OpenDisplay/commit/4ea3f6d2d224831f5ad1e02d34d70e2bc56706d5))
* let the calibration own the brightness and put back what it changed ([#13](https://github.com/m9tdev/OpenDisplay/issues/13)) ([45e2240](https://github.com/m9tdev/OpenDisplay/commit/45e224066a74ed645fa10e8b015e18c3a61070da))
* prefer the remembered key of a display that is off ([#11](https://github.com/m9tdev/OpenDisplay/issues/11)) ([fef2f9e](https://github.com/m9tdev/OpenDisplay/commit/fef2f9e8a97bfc100100681e5717e28cb75bb32f))
* put a synced display's brightness back at once when a calibration ends with the built-in display off ([#28](https://github.com/m9tdev/OpenDisplay/issues/28)) ([c07bf45](https://github.com/m9tdev/OpenDisplay/commit/c07bf457c5015014bab7d32032785a9a05e1da76))
* put back an unfinished calibration's settings when a missing display comes back ([#23](https://github.com/m9tdev/OpenDisplay/issues/23)) ([a03b51d](https://github.com/m9tdev/OpenDisplay/commit/a03b51d9cccf7d8b79270c8d4423231c115f51eb))
* reset a display's state when the monitor or DDC connection behind its ID changes ([#20](https://github.com/m9tdev/OpenDisplay/issues/20)) ([d8336f3](https://github.com/m9tdev/OpenDisplay/commit/d8336f398590c31313b4fc8878785fdab51e0ea7))
* save and match displays that are off in presets ([#9](https://github.com/m9tdev/OpenDisplay/issues/9)) ([df2d8df](https://github.com/m9tdev/OpenDisplay/commit/df2d8dfe5e9a499a8b0cec47955162f8402e0305))
* set synced displays again with the new curve after a calibration change with the built-in display off ([#29](https://github.com/m9tdev/OpenDisplay/issues/29)) ([09c0d60](https://github.com/m9tdev/OpenDisplay/commit/09c0d60efd6f2fbe296687f5dff5b67c8851628d))
* show an error when macOS does not let the app dim a display ([#26](https://github.com/m9tdev/OpenDisplay/issues/26)) ([de5ceb3](https://github.com/m9tdev/OpenDisplay/commit/de5ceb3dcffcc08305b6c67bdd3b2afc732c019c))
* show preset errors in Settings and say what Apply skips ([#12](https://github.com/m9tdev/OpenDisplay/issues/12)) ([d1c71a4](https://github.com/m9tdev/OpenDisplay/commit/d1c71a4729ffe46768979ec0a1a27e660334d03b))
* show the last on/off change of a display, and keep its row while it turns off ([#14](https://github.com/m9tdev/OpenDisplay/issues/14)) ([f04c8b2](https://github.com/m9tdev/OpenDisplay/commit/f04c8b21d056b3758ea8344def73f83a536f331b))
* stop calibration crashing when the external slider is at zero ([#18](https://github.com/m9tdev/OpenDisplay/issues/18)) ([8d677b6](https://github.com/m9tdev/OpenDisplay/commit/8d677b6c5b451ff7d5cc6e639daa4821ce49e7a7))

## [0.2.2](https://github.com/m9tdev/OpenDisplay/compare/v0.2.1...v0.2.2) (2026-11-02)


### Bug Fixes

* display guard follow-ups ([#5](https://github.com/m9tdev/OpenDisplay/issues/5)) ([96596df](https://github.com/m9tdev/OpenDisplay/commit/96596df228107159f080d9eb1f2625cedbfe21ea))

## [0.2.1](https://github.com/m9tdev/OpenDisplay/compare/v0.2.0...v0.2.1) (2026-11-02)


### Bug Fixes

* always keep a physical display on ([#3](https://github.com/m9tdev/OpenDisplay/issues/3)) ([f233b30](https://github.com/m9tdev/OpenDisplay/commit/f233b30e28a5975b69aad636c4f85f8f71e300d4))

## [0.2.0](https://github.com/m9tdev/OpenDisplay/compare/v0.1.2...v0.2.0) (2026-10-14)


### Features

* add a Buy Me a Coffee button to Settings ([2abe96b](https://github.com/m9tdev/OpenDisplay/commit/2abe96b367e8615c55153ad512205f6d5c6b612c))
* calibrate external display brightness by eye ([#1](https://github.com/m9tdev/OpenDisplay/issues/1)) ([bb76948](https://github.com/m9tdev/OpenDisplay/commit/bb76948719fd3cc120154ea4d572343c9ec78897))
