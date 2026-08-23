unit uSDRplay;

{*******************************************************************************

     Runtime (dlopen-based) binding to SDRplay's official API v3
     (sdrplay_api.dll), plus TSDRplayDevice - a TSDRDevice (uSDRDevice.pas)
     implementation for the SDRplay RSP1A (confirmed on this machine: a
     physically attached RSP1A, VID_1DF7&PID_3000, driver-bound and
     enumerated by the API as hwVer=SDRPLAY_RSP1A_ID=255).

     WHY DLOPEN INSTEAD OF LINK-TIME EXTERNAL:
     Same rationale as uHackRF.pas/uRTLSDR.pas - tolerant of the API not
     being installed at all (SDRplayLibLoaded stays False; Open then fails
     cleanly with a descriptive LastError). Unlike those two, though,
     sdrplay_api.dll isn't on PATH or in System32 even when the official
     SDRplay API installer HAS been run (confirmed on this machine: the
     installer places it at "%ProgramFiles%\SDRplay\API\x64\sdrplay_api.dll"
     only) - so LoadSDRplay tries the bare name first (in case a future
     install, or a different machine, does put it on PATH) and falls back
     to that known install path.

     THE SDRPLAY API IS A CLIENT/SERVICE ARCHITECTURE, NOT A DIRECT USB
     DRIVER BINDING: sdrplay_api.dll is a thin IPC client: sdrplay_api_Open
     auto-launches (or attaches to) a background sdrplay_apiService.exe,
     which does the actual USB communication - confirmed by watching that
     process appear during the probe run below, having not been running
     beforehand. This is transparent to this unit; sdrplay_api_Open/_Close
     bracket API-level (not per-device) state, called once per
     Open/Close here since only one TSDRplayDevice is ever live at a time
     in this app (see uSDRMain.pas's DetectAndOpenDevice).

     STRUCT LAYOUT AND EVERY FUNCTION SIGNATURE BELOW WERE CONFIRMED against
     the real, linked sdrplay_api.dll (v3.15, read directly from this
     machine's installed API headers at
     "C:\Program Files\SDRplay\API\inc\sdrplay_api*.h") AND the physically
     attached RSP1A, with a standalone throwaway probe program - same
     discipline uHackRF.pas/uRTLSDR.pas's own probes used. The probe:
     opened the API (v3.15), enumerated one device (hwVer=255, valid=1),
     selected it, read GetDeviceParams' default fsHz=2000000/rfHz=200000000/
     gRdB=50/LNAstate=0 (matching the header's documented defaults exactly,
     confirming every struct field is at the offset this binding assumes),
     set 2Msps/100MHz/gRdB=40/LNAstate=4/AGC-disabled, called Init and
     measured ~1.94M complex samples/s over 2 real seconds (matching the
     requested 2Msps), did a LIVE retune to 433.9MHz via sdrplay_api_Update
     while streaming (continued producing samples afterward, confirming
     Update works mid-stream), then Uninit/ReleaseDevice/Close all
     succeeded cleanly.

     THREADING:
     sdrplay_api_Init's stream callback runs on a thread the API's own
     service/client machinery manages internally (confirmed by the probe:
     Init returns immediately and samples arrive continuously afterward,
     the same "callback runs on a library-owned thread, returns
     immediately" shape as HackRF's hackrf_start_rx) - not the GUI thread,
     and not a thread this unit has to create/manage itself, unlike
     uRTLSDR.pas's blocking rtlsdr_read_async. SDRplayStreamCallback (the
     module-level cdecl callback) only writes into a TSDRRingBuffer, same
     discipline as both sibling backends.

     SAMPLE FORMAT - THE ONE GENUINE STRUCTURAL DIFFERENCE FROM HackRF/
     RTL-SDR: the SDRplay stream callback hands over I and Q as two
     SEPARATE signed 16-bit arrays (xi, xq), not one interleaved byte
     buffer - confirmed by sdrplay_api_callback.h's own
     sdrplay_api_StreamCallback_t signature. OnRawData interleaves them
     into a local (I0,Q0,I1,Q1,...) SmallInt buffer before handing the
     resulting bytes to the shared TSDRRingBuffer, so TryReadEpoch can
     reuse the exact same "read newest NeedBytes, reinterpret" contract
     the other two backends already established - only the reinterpret
     step (signed 16-bit here, vs HackRF's signed 8-bit / RTL-SDR's
     unsigned 8-bit) actually differs.

     GAIN MODEL:
     RSP1A's own gain chain is IF gain reduction (gRdB, 20-59dB - the
     NORMAL_MIN_GR floor of 20 is used rather than the EXTENDED_MIN_GR
     0dB floor, matching SDRplay's own recommended default range and
     avoiding the extra care the extended range needs) plus a separate
     LNA state (0-9, RSPIA_NUM_LNA_STATES) - two genuinely independent
     controls, both bundled under the SAME sdrplay_api_Update_Tuner_Gr
     reason code per the API's own design (sdrplay_api_GainT holds both
     gRdB and LNAstate together). Exposed as GainStages[0]/[1]
     respectively - LNAstate as a raw 0-9 state index, not a dB value (the
     actual attenuation per step varies by frequency band and isn't a
     single published table), hence UnitSuffix left blank rather than the
     'dB' every other stage in this app uses (see that field's own comment
     in uSDRDevice.pas). GainStages[2] (gkBoolean) is RF Notch
     (Rsp1aParamsT.rfNotchEnable - a DEVICE-level, not per-tuner, field,
     unlike every other control here) rather than the DAB notch
     (rfDabNotchEnable) - RF notch (broadcast AM/FM) is the more generally
     useful one for general-purpose SDR use, and this app's UI only has
     one boolean gain-stage slot (see uSDRMain.pas's ApplyDeviceCapabilities
     "numeric stages fill 0/1, first boolean fills 2" convention) - DAB
     notch is left unexposed, a known scope limitation, not an oversight.
     BoolOptions[0] is Bias-T (Rsp1aTunerParamsT.biasTEnable, per-tuner),
     matching the "always slot 0" convention uSDRMain.pas's BiasTCheckBox
     already assumes for both other backends.

     AGC is explicitly disabled in Open (ctrlParams.agc.enable :=
     sdrplay_api_AGC_DISABLE) - the API's own default is
     sdrplay_api_AGC_50HZ (AGC ON), which would otherwise fight the manual
     gRdB control this unit exposes, exactly as confirmed necessary by the
     probe (AGC was explicitly disabled there before Init).

     SAMPLE RATE / BANDWIDTH: RSP1A's ADC natively covers roughly 2-10.66
     Msps with no decimation. Capabilities.SampleRates offers a short
     preset list across that range, matching uRTLSDR.pas's own "short
     preset list of common values" convention rather than an arbitrary
     continuous edit. CurrentBwType picks the widest sdrplay_api_Bw_MHzT
     analog filter not exceeding the chosen ADC rate (same "round down,
     never exceed" idiom as HackRF's own
     hackrf_compute_baseband_filter_bw_round_down_lt) - RSP1A's available
     filter steps (200/300/600kHz, 1.536/5/6/7/8MHz) are sparser than
     HackRF's, so this sometimes leaves a real gap (e.g. 3Msps rounds down
     to a 1.536MHz filter) - conservative/narrower rather than wrong, and
     documented here rather than silently accepted.

     BELOW 2Msps (DECIMATION): one additional preset, 1.0Msps, is offered
     below the ADC's own native floor via the API's own decimation stage
     (sdrplay_api_DecimationT, ctrlParams.decimation - confirmed present
     and documented in the real, linked sdrplay_api.h/_control.h, v3.15,
     read directly from "C:\Program Files\SDRplay\API\inc\" on this
     machine) rather than anything implemented here in software: the ADC
     itself still runs at 2.0Msps (fsFreq.fsHz unchanged), and
     decimationFactor=2 has the API's own DSP pipeline halve the rate
     before any of it ever reaches OnRawData - entirely transparent to
     the rest of this app (TryReadEpoch/SampleRateHz already report
     whatever FSampleRateHz says, and nothing downstream cares whether a
     given rate came from the raw ADC or the API's decimator). Only this
     one specific case (2.0Msps ADC / factor 2 -> 1.0Msps effective) is
     implemented - a single, deliberately narrow, tested mapping rather
     than a general "pick any effective rate, derive ADC rate + factor"
     function; extend SetSampleRateHz's own decimation branch if a future
     caller needs a different decimated rate. wideBandSignal is set True:
     this app's own wideband-capture-plus-software-tune design (see
     uSDRRFSource.pas's own header comment) means the pre-decimation
     capture still spans multiple stations across the band, not a single
     already-narrowband signal, so the decimation filter should use the
     less aggressive/wider setting the API reserves for that case, not
     the tighter one meant for an already-narrow input.
     CurrentBwType's own analog-filter choice, when decimating, is
     STILL based on the ADC's real 2.0Msps rate, not the 1.0Msps
     effective one - the analog front-end filter runs before the ADC/
     decimation entirely, so narrowing it to match the post-decimation
     rate would needlessly clip the outer part of the very passband the
     decimation filter is about to correctly downsample; only the
     digital decimation filter's own passband should track the EFFECTIVE
     rate, and the API handles that internally.

*******************************************************************************}

{$mode objfpc}{$H+}
{$MINENUMSIZE 4}

interface

uses
  Classes, SysUtils, DynLibs, newVMComplex, uSDRDevice;

const
  {$IFDEF WINDOWS}
  SDRplayLibCandidates: array[0..0] of string = ('sdrplay_api.dll');
  // Confirmed present at this exact path by the official SDRplay API
  // installer on this machine - see this unit's header comment for why
  // the bare name above (tried first) doesn't resolve on its own.
  SDRplayLibFallbackPath = 'C:\Program Files\SDRplay\API\x64\sdrplay_api.dll';
  {$ELSE}
    {$IFDEF DARWIN}
  // The OFFICIAL SDRplay API installer (from sdrplay.com/api - NOT the
  // SDRconnect end-user app, which statically links its own private
  // client code and exposes no shared library at all) puts a genuine fat
  // x86_64+arm64 libsdrplay_api.so.3.15 under
  // /Library/SDRplayAPI/<version>/lib, and symlinks a versionless
  // libsdrplay_api.dylib into /usr/local/lib - confirmed via `lipo -info`
  // on this machine (Apple Silicon). /usr/local/lib IS on dyld's default
  // fallback search path (unlike uHackRF.pas/uRTLSDR.pas's /opt/local/lib
  // MacPorts installs), so the bare name alone is expected to resolve,
  // but the full path is included as a fallback in case a future install
  // changes that. A stale MacPorts `SDRplay3` port (x86_64-only, v3.07.1)
  // may also be present on a machine that tried that route first - its
  // library lives under /opt/local/lib and is NOT arm64-compatible, so it
  // is deliberately NOT in this candidate list; its conflicting
  // sdrplay_apiService LaunchDaemon must also be unloaded/disabled
  // (`sudo launchctl bootout system/org.macports.sdrplay_service`) so it
  // doesn't fight the official service over the USB device.
  SDRplayLibCandidates: array[0..1] of string = (
    'libsdrplay_api.dylib',
    '/usr/local/lib/libsdrplay_api.dylib'
  );
  SDRplayLibFallbackPath = '';
    {$ELSE}
  SDRplayLibCandidates: array[0..0] of string = ('libsdrplay_api.so.3');
  SDRplayLibFallbackPath = '';   // no Linux machine available to confirm an install path
    {$ENDIF}
  {$ENDIF}

  SDRPLAY_MAX_DEVICES = 16;
  SDRPLAY_MAX_SER_NO_LEN = 64;
  SDRPLAY_RSP1A_ID = 255;
  RSP1A_NUM_LNA_STATES = 10;

  // Ring buffer capacity - same "plenty of headroom, not a tuned minimum"
  // rationale as uRTLSDR.pas's RTLSDRRingBytes. RSP1A's samples are twice
  // the byte width of RTL-SDR's (16-bit vs 8-bit per I/Q component) at a
  // broadly similar practical sample rate, so this is sized up accordingly.
  SDRplayRingBytes = 8 * 1024 * 1024;

type
  // ---- Enums (all forced to 4-byte width via {$MINENUMSIZE 4} above, to
  // match C's int-sized enums - required for every struct below that
  // embeds one, not just as a documentation nicety). ----
  sdrplay_api_ErrT = (
    sdrplay_api_Success = 0, sdrplay_api_Fail = 1, sdrplay_api_InvalidParam = 2,
    sdrplay_api_OutOfRange = 3, sdrplay_api_GainUpdateError = 4, sdrplay_api_RfUpdateError = 5,
    sdrplay_api_FsUpdateError = 6, sdrplay_api_HwError = 7, sdrplay_api_AliasingError = 8,
    sdrplay_api_AlreadyInitialised = 9, sdrplay_api_NotInitialised = 10, sdrplay_api_NotEnabled = 11,
    sdrplay_api_HwVerError = 12, sdrplay_api_OutOfMemError = 13, sdrplay_api_ServiceNotResponding = 14,
    sdrplay_api_StartPending = 15, sdrplay_api_StopPending = 16, sdrplay_api_InvalidMode = 17,
    sdrplay_api_FailedVerification1 = 18, sdrplay_api_FailedVerification2 = 19,
    sdrplay_api_FailedVerification3 = 20, sdrplay_api_FailedVerification4 = 21,
    sdrplay_api_FailedVerification5 = 22, sdrplay_api_FailedVerification6 = 23,
    sdrplay_api_InvalidServiceVersion = 24
  );

  sdrplay_api_TunerSelectT = (
    sdrplay_api_Tuner_Neither = 0, sdrplay_api_Tuner_A = 1, sdrplay_api_Tuner_B = 2, sdrplay_api_Tuner_Both = 3
  );

  sdrplay_api_RspDuoModeT = (
    sdrplay_api_RspDuoMode_Unknown = 0, sdrplay_api_RspDuoMode_Single_Tuner = 1,
    sdrplay_api_RspDuoMode_Dual_Tuner = 2, sdrplay_api_RspDuoMode_Master = 4, sdrplay_api_RspDuoMode_Slave = 8
  );

  sdrplay_api_TransferModeT = (sdrplay_api_ISOCH = 0, sdrplay_api_BULK = 1);

  sdrplay_api_Bw_MHzT = (sdrplay_api_BW_Undefined = 0, sdrplay_api_BW_0_200 = 200, sdrplay_api_BW_0_300 = 300,
    sdrplay_api_BW_0_600 = 600, sdrplay_api_BW_1_536 = 1536, sdrplay_api_BW_5_000 = 5000,
    sdrplay_api_BW_6_000 = 6000, sdrplay_api_BW_7_000 = 7000, sdrplay_api_BW_8_000 = 8000);
  sdrplay_api_If_kHzT = (sdrplay_api_IF_Undefined = -1, sdrplay_api_IF_Zero = 0, sdrplay_api_IF_0_450 = 450,
    sdrplay_api_IF_1_620 = 1620, sdrplay_api_IF_2_048 = 2048);
  sdrplay_api_LoModeT = (sdrplay_api_LO_Undefined = 0, sdrplay_api_LO_Auto = 1, sdrplay_api_LO_120MHz = 2,
    sdrplay_api_LO_144MHz = 3, sdrplay_api_LO_168MHz = 4);
  sdrplay_api_MinGainReductionT = (sdrplay_api_EXTENDED_MIN_GR = 0, sdrplay_api_NORMAL_MIN_GR = 20);

  sdrplay_api_AgcControlT = (sdrplay_api_AGC_DISABLE = 0, sdrplay_api_AGC_100HZ = 1, sdrplay_api_AGC_50HZ = 2,
    sdrplay_api_AGC_5HZ = 3, sdrplay_api_AGC_CTRL_EN = 4);
  sdrplay_api_AdsbModeT = (sdrplay_api_ADSB_DECIMATION = 0, sdrplay_api_ADSB_NO_DECIMATION_LOWPASS = 1,
    sdrplay_api_ADSB_NO_DECIMATION_BANDPASS_2MHZ = 2, sdrplay_api_ADSB_NO_DECIMATION_BANDPASS_3MHZ = 3);

  sdrplay_api_Rsp2_AntennaSelectT = (sdrplay_api_Rsp2_ANTENNA_A = 5, sdrplay_api_Rsp2_ANTENNA_B = 6);
  sdrplay_api_Rsp2_AmPortSelectT = (sdrplay_api_Rsp2_AMPORT_1 = 1, sdrplay_api_Rsp2_AMPORT_2 = 0);
  sdrplay_api_RspDuo_AmPortSelectT = (sdrplay_api_RspDuo_AMPORT_1 = 1, sdrplay_api_RspDuo_AMPORT_2 = 0);
  sdrplay_api_RspDx_AntennaSelectT = (sdrplay_api_RspDx_ANTENNA_A = 0, sdrplay_api_RspDx_ANTENNA_B = 1, sdrplay_api_RspDx_ANTENNA_C = 2);
  sdrplay_api_RspDx_HdrModeBwT = (sdrplay_api_RspDx_HDRMODE_BW_0_200 = 0, sdrplay_api_RspDx_HDRMODE_BW_0_500 = 1,
    sdrplay_api_RspDx_HDRMODE_BW_1_200 = 2, sdrplay_api_RspDx_HDRMODE_BW_1_700 = 3);

  sdrplay_api_PowerOverloadCbEventIdT = (sdrplay_api_Overload_Detected = 0, sdrplay_api_Overload_Corrected = 1);
  sdrplay_api_RspDuoModeCbEventIdT = (sdrplay_api_MasterInitialised = 0, sdrplay_api_SlaveAttached = 1,
    sdrplay_api_SlaveDetached = 2, sdrplay_api_SlaveInitialised = 3, sdrplay_api_SlaveUninitialised = 4,
    sdrplay_api_MasterDllDisappeared = 5, sdrplay_api_SlaveDllDisappeared = 6);
  sdrplay_api_EventT = (sdrplay_api_GainChange = 0, sdrplay_api_PowerOverloadChange = 1,
    sdrplay_api_DeviceRemoved = 2, sdrplay_api_RspDuoModeChange = 3, sdrplay_api_DeviceFailure = 4);

  // ---- Structs, declared bottom-up as each is embedded by the next -
  // every field, in the exact order the real headers declare them, is
  // required to keep every LATER field's offset correct even where this
  // application only reads/writes RSP1A-specific ones (e.g.
  // sdrplay_api_DevParamsT's rsp2Params/rspDuoParams/rspDxParams sit
  // between rsp1aParams and the struct's end, so they must be sized
  // correctly even though nothing here ever touches their contents). ----

  sdrplay_api_FsFreqT = record
    fsHz: Double;
    syncUpdate: Byte;
    reCal: Byte;
  end;

  sdrplay_api_SyncUpdateT = record
    sampleNum: LongWord;
    period: LongWord;
  end;

  sdrplay_api_ResetFlagsT = record
    resetGainUpdate: Byte;
    resetRfUpdate: Byte;
    resetFsUpdate: Byte;
  end;

  sdrplay_api_Rsp1aParamsT = record
    rfNotchEnable: Byte;
    rfDabNotchEnable: Byte;
  end;

  sdrplay_api_Rsp1aTunerParamsT = record
    biasTEnable: Byte;
  end;

  sdrplay_api_Rsp2ParamsT = record
    extRefOutputEn: Byte;
  end;

  sdrplay_api_Rsp2TunerParamsT = record
    biasTEnable: Byte;
    amPortSel: sdrplay_api_Rsp2_AmPortSelectT;
    antennaSel: sdrplay_api_Rsp2_AntennaSelectT;
    rfNotchEnable: Byte;
  end;

  sdrplay_api_RspDuoParamsT = record
    extRefOutputEn: LongInt;
  end;

  sdrplay_api_RspDuo_ResetSlaveFlagsT = record
    resetGainUpdate: Byte;
    resetRfUpdate: Byte;
  end;

  sdrplay_api_RspDuoTunerParamsT = record
    biasTEnable: Byte;
    tuner1AmPortSel: sdrplay_api_RspDuo_AmPortSelectT;
    tuner1AmNotchEnable: Byte;
    rfNotchEnable: Byte;
    rfDabNotchEnable: Byte;
    resetSlaveFlags: sdrplay_api_RspDuo_ResetSlaveFlagsT;
  end;

  sdrplay_api_RspDxParamsT = record
    hdrEnable: Byte;
    biasTEnable: Byte;
    antennaSel: sdrplay_api_RspDx_AntennaSelectT;
    rfNotchEnable: Byte;
    rfDabNotchEnable: Byte;
  end;

  sdrplay_api_RspDxTunerParamsT = record
    hdrBw: sdrplay_api_RspDx_HdrModeBwT;
  end;

  sdrplay_api_DevParamsT = record
    ppm: Double;
    fsFreq: sdrplay_api_FsFreqT;
    syncUpdate: sdrplay_api_SyncUpdateT;
    resetFlags: sdrplay_api_ResetFlagsT;
    mode: sdrplay_api_TransferModeT;
    samplesPerPkt: LongWord;
    rsp1aParams: sdrplay_api_Rsp1aParamsT;
    rsp2Params: sdrplay_api_Rsp2ParamsT;
    rspDuoParams: sdrplay_api_RspDuoParamsT;
    rspDxParams: sdrplay_api_RspDxParamsT;
  end;
  Psdrplay_api_DevParamsT = ^sdrplay_api_DevParamsT;

  sdrplay_api_GainValuesT = record
    curr: Single;
    max: Single;
    min: Single;
  end;

  sdrplay_api_GainT = record
    gRdB: LongInt;
    LNAstate: Byte;
    syncUpdate: Byte;
    minGr: sdrplay_api_MinGainReductionT;
    gainVals: sdrplay_api_GainValuesT;
  end;

  sdrplay_api_RfFreqT = record
    rfHz: Double;
    syncUpdate: Byte;
  end;

  sdrplay_api_DcOffsetTunerT = record
    dcCal: Byte;
    speedUp: Byte;
    trackTime: LongInt;
    refreshRateTime: LongInt;
  end;

  sdrplay_api_TunerParamsT = record
    bwType: sdrplay_api_Bw_MHzT;
    ifType: sdrplay_api_If_kHzT;
    loMode: sdrplay_api_LoModeT;
    gain: sdrplay_api_GainT;
    rfFreq: sdrplay_api_RfFreqT;
    dcOffsetTuner: sdrplay_api_DcOffsetTunerT;
  end;

  sdrplay_api_DcOffsetT = record
    DCenable: Byte;
    IQenable: Byte;
  end;

  sdrplay_api_DecimationT = record
    enable: Byte;
    decimationFactor: Byte;
    wideBandSignal: Byte;
  end;

  sdrplay_api_AgcT = record
    enable: sdrplay_api_AgcControlT;
    setPoint_dBfs: LongInt;
    attack_ms: Word;
    decay_ms: Word;
    decay_delay_ms: Word;
    decay_threshold_dB: Word;
    syncUpdate: LongInt;
  end;

  sdrplay_api_ControlParamsT = record
    dcOffset: sdrplay_api_DcOffsetT;
    decimation: sdrplay_api_DecimationT;
    agc: sdrplay_api_AgcT;
    adsbMode: sdrplay_api_AdsbModeT;
  end;

  sdrplay_api_RxChannelParamsT = record
    tunerParams: sdrplay_api_TunerParamsT;
    ctrlParams: sdrplay_api_ControlParamsT;
    rsp1aTunerParams: sdrplay_api_Rsp1aTunerParamsT;
    rsp2TunerParams: sdrplay_api_Rsp2TunerParamsT;
    rspDuoTunerParams: sdrplay_api_RspDuoTunerParamsT;
    rspDxTunerParams: sdrplay_api_RspDxTunerParamsT;
  end;
  Psdrplay_api_RxChannelParamsT = ^sdrplay_api_RxChannelParamsT;

  sdrplay_api_DeviceT = record
    SerNo: array[0..SDRPLAY_MAX_SER_NO_LEN-1] of AnsiChar;
    hwVer: Byte;
    tuner: sdrplay_api_TunerSelectT;
    rspDuoMode: sdrplay_api_RspDuoModeT;
    valid: Byte;
    rspDuoSampleFreq: Double;
    dev: Pointer;
  end;
  Psdrplay_api_DeviceT = ^sdrplay_api_DeviceT;

  sdrplay_api_DeviceParamsT = record
    devParams: Psdrplay_api_DevParamsT;
    rxChannelA: Psdrplay_api_RxChannelParamsT;
    rxChannelB: Psdrplay_api_RxChannelParamsT;
  end;
  Psdrplay_api_DeviceParamsT = ^sdrplay_api_DeviceParamsT;

  sdrplay_api_ErrorInfoT = record
    fileName: array[0..255] of AnsiChar;
    funcName: array[0..255] of AnsiChar;
    line: LongInt;
    msg: array[0..1023] of AnsiChar;
  end;
  Psdrplay_api_ErrorInfoT = ^sdrplay_api_ErrorInfoT;

  sdrplay_api_GainCbParamT = record
    gRdB: LongWord;
    lnaGRdB: LongWord;
    currGain: Double;
  end;

  sdrplay_api_PowerOverloadCbParamT = record
    powerOverloadChangeType: sdrplay_api_PowerOverloadCbEventIdT;
  end;

  sdrplay_api_RspDuoModeCbParamT = record
    modeChangeType: sdrplay_api_RspDuoModeCbEventIdT;
  end;

  sdrplay_api_EventParamsT = record
    case Integer of
      0: (gainParams: sdrplay_api_GainCbParamT);
      1: (powerOverloadParams: sdrplay_api_PowerOverloadCbParamT);
      2: (rspDuoModeParams: sdrplay_api_RspDuoModeCbParamT);
  end;
  Psdrplay_api_EventParamsT = ^sdrplay_api_EventParamsT;

  sdrplay_api_StreamCbParamsT = record
    firstSampleNum: LongWord;
    grChanged: LongInt;
    rfChanged: LongInt;
    fsChanged: LongInt;
    numSamples: LongWord;
  end;
  Psdrplay_api_StreamCbParamsT = ^sdrplay_api_StreamCbParamsT;

  sdrplay_api_StreamCallback_t = procedure(xi, xq: PSmallInt; params: Psdrplay_api_StreamCbParamsT;
    numSamples: LongWord; reset: LongWord; cbContext: Pointer); cdecl;
  sdrplay_api_EventCallback_t = procedure(eventId: sdrplay_api_EventT; tuner: sdrplay_api_TunerSelectT;
    params: Psdrplay_api_EventParamsT; cbContext: Pointer); cdecl;

  sdrplay_api_CallbackFnsT = record
    StreamACbFn: sdrplay_api_StreamCallback_t;
    StreamBCbFn: sdrplay_api_StreamCallback_t;
    EventCbFn: sdrplay_api_EventCallback_t;
  end;

  // Reason-for-update bitmasks are OR-able flags, not a Pascal enum (values
  // like sdrplay_api_Update_Tuner_Frf and sdrplay_api_Update_Dev_Fs are
  // legitimately combined in one Update call - see SetSampleRateHz below,
  // which sets both the sample rate AND the matching analog filter in one
  // call) - plain LongWord constants, matching how uSDRDevice.pas's own
  // StageIndex-based dispatch already favours plain values over enums for
  // anything that gets combined/compared arithmetically.
  sdrplay_api_ReasonForUpdateT = LongWord;
  sdrplay_api_ReasonForUpdateExtension1T = LongWord;

const
  sdrplay_api_Update_None                    = LongWord(0);
  sdrplay_api_Update_Dev_Fs                  = LongWord($00000001);
  sdrplay_api_Update_Rsp1a_BiasTControl      = LongWord($00000010);
  sdrplay_api_Update_Rsp1a_RfNotchControl    = LongWord($00000020);
  sdrplay_api_Update_Tuner_Gr                = LongWord($00008000);
  sdrplay_api_Update_Tuner_Frf               = LongWord($00020000);
  sdrplay_api_Update_Tuner_BwType            = LongWord($00040000);
  sdrplay_api_Update_Ctrl_Decimation         = LongWord($00800000);
  sdrplay_api_Update_Ctrl_Agc                = LongWord($01000000);
  sdrplay_api_Update_Ext1_None                = LongWord(0);

type
  Tsdrplay_api_Open = function(): sdrplay_api_ErrT; cdecl;
  Tsdrplay_api_Close = function(): sdrplay_api_ErrT; cdecl;
  Tsdrplay_api_ApiVersion = function(var apiVer: Single): sdrplay_api_ErrT; cdecl;
  Tsdrplay_api_GetDevices = function(devices: Psdrplay_api_DeviceT; var numDevs: LongWord; maxDevs: LongWord): sdrplay_api_ErrT; cdecl;
  Tsdrplay_api_SelectDevice = function(device: Psdrplay_api_DeviceT): sdrplay_api_ErrT; cdecl;
  Tsdrplay_api_ReleaseDevice = function(device: Psdrplay_api_DeviceT): sdrplay_api_ErrT; cdecl;
  Tsdrplay_api_GetErrorString = function(err: sdrplay_api_ErrT): PAnsiChar; cdecl;
  Tsdrplay_api_GetDeviceParams = function(dev: Pointer; var deviceParams: Psdrplay_api_DeviceParamsT): sdrplay_api_ErrT; cdecl;
  Tsdrplay_api_Init = function(dev: Pointer; var callbackFns: sdrplay_api_CallbackFnsT; cbContext: Pointer): sdrplay_api_ErrT; cdecl;
  Tsdrplay_api_Uninit = function(dev: Pointer): sdrplay_api_ErrT; cdecl;
  Tsdrplay_api_Update = function(dev: Pointer; tuner: sdrplay_api_TunerSelectT;
    reasonForUpdate: sdrplay_api_ReasonForUpdateT; reasonForUpdateExt1: sdrplay_api_ReasonForUpdateExtension1T): sdrplay_api_ErrT; cdecl;

var
  sdrplay_api_Open: Tsdrplay_api_Open;
  sdrplay_api_Close: Tsdrplay_api_Close;
  sdrplay_api_ApiVersion: Tsdrplay_api_ApiVersion;
  sdrplay_api_GetDevices: Tsdrplay_api_GetDevices;
  sdrplay_api_SelectDevice: Tsdrplay_api_SelectDevice;
  sdrplay_api_ReleaseDevice: Tsdrplay_api_ReleaseDevice;
  sdrplay_api_GetErrorString: Tsdrplay_api_GetErrorString;
  sdrplay_api_GetDeviceParams: Tsdrplay_api_GetDeviceParams;
  sdrplay_api_Init: Tsdrplay_api_Init;
  sdrplay_api_Uninit: Tsdrplay_api_Uninit;
  sdrplay_api_Update: Tsdrplay_api_Update;

  SDRplayLibLoaded: Boolean = False;

type
  { TSDRplayDevice }
  TSDRplayDevice = class(TSDRDevice)
  private
    FDeviceRec: sdrplay_api_DeviceT;
    FDeviceSelected: Boolean;   // True once SelectDevice succeeded (ReleaseDevice needed on Close)
    FDevParams: Psdrplay_api_DeviceParamsT;
    FRing: TSDRRingBuffer;

    function CallFailed(Err: sdrplay_api_ErrT; const Routine: string): Boolean;
    procedure BuildCapabilities;
    function CurrentBwType(RateHz: Double): sdrplay_api_Bw_MHzT;
  public
    constructor Create;
    destructor Destroy; override;

    function Open: Boolean; override;
    procedure Close; override;

    function SetFrequencyHz(Hz: QWord): Boolean; override;
    function SetSampleRateHz(Hz: Double): Boolean; override;
    function SetGain(StageIndex: Integer; Value: Double): Boolean; override;
    function SetBoolOption(OptionIndex: Integer; Value: Boolean): Boolean; override;

    function StartRX: Boolean; override;
    function StopRX: Boolean; override;

    // Called only from SDRplayStreamCallback, on the API's own service
    // thread.
    procedure OnRawData(xi, xq: PSmallInt; NumSamples: Integer);

    function TryReadEpoch(N: Integer; out IQ: TVMobjZ): Boolean; override;
  end;

implementation

var
  SDRplayHandle: TLibHandle = NilHandle;

function Load(const Name: string): Pointer;
begin
  Result := GetProcedureAddress(SDRplayHandle, Name);
end;

procedure LoadSDRplayAddresses;
begin
  Pointer(sdrplay_api_Open)            := Load('sdrplay_api_Open');
  Pointer(sdrplay_api_Close)           := Load('sdrplay_api_Close');
  Pointer(sdrplay_api_ApiVersion)      := Load('sdrplay_api_ApiVersion');
  Pointer(sdrplay_api_GetDevices)      := Load('sdrplay_api_GetDevices');
  Pointer(sdrplay_api_SelectDevice)    := Load('sdrplay_api_SelectDevice');
  Pointer(sdrplay_api_ReleaseDevice)   := Load('sdrplay_api_ReleaseDevice');
  Pointer(sdrplay_api_GetErrorString)  := Load('sdrplay_api_GetErrorString');
  Pointer(sdrplay_api_GetDeviceParams) := Load('sdrplay_api_GetDeviceParams');
  Pointer(sdrplay_api_Init)            := Load('sdrplay_api_Init');
  Pointer(sdrplay_api_Uninit)          := Load('sdrplay_api_Uninit');
  Pointer(sdrplay_api_Update)          := Load('sdrplay_api_Update');
end;

function SDRplayLibCandidateList: string;
var
  i: Integer;
begin
  Result := '';
  for i := Low(SDRplayLibCandidates) to High(SDRplayLibCandidates) do begin
    if i > Low(SDRplayLibCandidates) then Result := Result + ', ';
    Result := Result + SDRplayLibCandidates[i];
  end;
end;

function InitializeSDRplayLib: Boolean;
var
  i: Integer;
begin
  if SDRplayHandle = NilHandle then begin
    for i := Low(SDRplayLibCandidates) to High(SDRplayLibCandidates) do begin
      SDRplayHandle := LoadLibrary(SDRplayLibCandidates[i]);
      if SDRplayHandle <> NilHandle then Break;
    end;
    if (SDRplayHandle = NilHandle) and (SDRplayLibFallbackPath <> '') then
      SDRplayHandle := LoadLibrary(SDRplayLibFallbackPath);
    if SDRplayHandle <> NilHandle then LoadSDRplayAddresses;
  end;
  Result := SDRplayHandle <> NilHandle;
end;

// Module-level cdecl callbacks the API's service thread calls directly -
// cbContext is the TSDRplayDevice instance passed to sdrplay_api_Init (see
// TSDRplayDevice.StartRX), cast back unchanged. SDRplayEventCallback does
// nothing but exist: sdrplay_api_Init requires a non-nil EventCbFn (the
// probe confirmed events - a GainChange at Init, another at retune, an
// Overload at Uninit - fire routinely under normal use, not just error
// conditions), but this app has no use for them yet.
procedure SDRplayStreamCallback(xi, xq: PSmallInt; params: Psdrplay_api_StreamCbParamsT;
  numSamples: LongWord; reset: LongWord; cbContext: Pointer); cdecl;
var
  Dev: TSDRplayDevice;
begin
  Dev := TSDRplayDevice(cbContext);
  if Assigned(Dev) then Dev.OnRawData(xi, xq, numSamples);
end;

procedure SDRplayEventCallback(eventId: sdrplay_api_EventT; tuner: sdrplay_api_TunerSelectT;
  params: Psdrplay_api_EventParamsT; cbContext: Pointer); cdecl;
begin
  // Intentionally empty - see this function's own comment above.
end;

{ TSDRplayDevice }

constructor TSDRplayDevice.Create;
begin
  inherited Create;
  FRing := TSDRRingBuffer.Create(SDRplayRingBytes);
  FCenterFreqHz := 100000000;
  FSampleRateHz := 2000000.0;

  // Placeholder Capabilities, replaced by BuildCapabilities once a real
  // device is open - see uRTLSDR.pas's constructor for the same rationale
  // (this record just needs to not be garbage before Open succeeds).
  FCapabilities.DeviceName := 'SDRplay RSP1A';
  FCapabilities.MinFreqHz := 1.0e3;
  FCapabilities.MaxFreqHz := 2000.0e6;
  // [0] (1.0Msps) is below the ADC's own native floor - reached via the
  // API's own decimation stage, not a real ADC rate; see this unit's own
  // header comment (BELOW 2Msps (DECIMATION)) for how SetSampleRateHz
  // gets there.
  SetLength(FCapabilities.SampleRates, 9);
  FCapabilities.SampleRates[0] := 1.0e6;
  FCapabilities.SampleRates[1] := 2.0e6;
  FCapabilities.SampleRates[2] := 3.0e6;
  FCapabilities.SampleRates[3] := 4.0e6;
  FCapabilities.SampleRates[4] := 5.0e6;
  FCapabilities.SampleRates[5] := 6.0e6;
  FCapabilities.SampleRates[6] := 8.0e6;
  FCapabilities.SampleRates[7] := 9.0e6;
  FCapabilities.SampleRates[8] := 10.0e6;
  FCapabilities.DefaultSampleRateHz := 2.0e6;
  FCapabilities.DefaultFreqHz := 100000000;

  SetLength(FCapabilities.BoolOptions, 1);
  FCapabilities.BoolOptions[0].Name := 'Bias-T (Antenna Power)';
end;

destructor TSDRplayDevice.Destroy;
begin
  if FStreaming then StopRX;
  if FIsOpen then Close;
  FRing.Free;
  inherited Destroy;
end;

function TSDRplayDevice.CallFailed(Err: sdrplay_api_ErrT; const Routine: string): Boolean;
begin
  Result := Err <> sdrplay_api_Success;
  if Result then begin
    if Assigned(sdrplay_api_GetErrorString) then
      FLastError := Routine + ' failed: ' + sdrplay_api_GetErrorString(Err)
    else
      FLastError := Routine + ' failed with code ' + IntToStr(Ord(Err));
  end;
end;

// Numeric gain stages only - see this unit's header comment (GAIN MODEL)
// for why LNAstate's DiscreteValues are the raw 0-9 state index rather
// than a dB figure.
procedure TSDRplayDevice.BuildCapabilities;
var
  i: Integer;
begin
  SetLength(FCapabilities.GainStages, 3);
  FCapabilities.GainStages[0].Name := 'IF Gain Reduction';
  FCapabilities.GainStages[0].Kind := gkContinuous;
  FCapabilities.GainStages[0].Min := Ord(sdrplay_api_NORMAL_MIN_GR);
  FCapabilities.GainStages[0].Max := 59;
  FCapabilities.GainStages[0].Step := 1;
  FCapabilities.GainStages[0].UnitSuffix := 'dB';

  FCapabilities.GainStages[1].Name := 'LNA State';
  FCapabilities.GainStages[1].Kind := gkDiscreteList;
  FCapabilities.GainStages[1].UnitSuffix := '';
  SetLength(FCapabilities.GainStages[1].DiscreteValues, RSP1A_NUM_LNA_STATES);
  for i := 0 to RSP1A_NUM_LNA_STATES - 1 do
    FCapabilities.GainStages[1].DiscreteValues[i] := i;

  FCapabilities.GainStages[2].Name := 'RF Notch';
  FCapabilities.GainStages[2].Kind := gkBoolean;
end;

// Widest analog filter not exceeding RateHz - see this unit's header
// comment (SAMPLE RATE / BANDWIDTH) for the "round down, sometimes
// leaves a gap" trade-off. RateHz is passed explicitly, not read from
// FSampleRateHz directly, because the two calling contexts genuinely
// need different rates: SetSampleRateHz's decimated-rate branch must
// pass the real ADC rate (2.0Msps) here, not the lower EFFECTIVE rate
// FSampleRateHz itself ends up holding - see this unit's own header
// comment (BELOW 2Msps (DECIMATION)) for why.
function TSDRplayDevice.CurrentBwType(RateHz: Double): sdrplay_api_Bw_MHzT;
var
  RateKHz: Double;
begin
  RateKHz := RateHz / 1000.0;
  if RateKHz >= 8000 then Result := sdrplay_api_BW_8_000
  else if RateKHz >= 7000 then Result := sdrplay_api_BW_7_000
  else if RateKHz >= 6000 then Result := sdrplay_api_BW_6_000
  else if RateKHz >= 5000 then Result := sdrplay_api_BW_5_000
  else if RateKHz >= 1536 then Result := sdrplay_api_BW_1_536
  else if RateKHz >= 600 then Result := sdrplay_api_BW_0_600
  else if RateKHz >= 300 then Result := sdrplay_api_BW_0_300
  else Result := sdrplay_api_BW_0_200;
end;

function TSDRplayDevice.Open: Boolean;
var
  Devices: array[0..SDRPLAY_MAX_DEVICES-1] of sdrplay_api_DeviceT;
  NumDevs: LongWord;
  i, ChosenIdx: Integer;
begin
  Result := False;
  if FIsOpen then begin Result := True; Exit; end;

  if not SDRplayLibLoaded then begin
    FLastError := 'SDRplay API runtime library (' + SDRplayLibCandidateList + ') not found';
    Exit;
  end;

  if CallFailed(sdrplay_api_Open(), 'sdrplay_api_Open') then Exit;

  NumDevs := 0;
  if CallFailed(sdrplay_api_GetDevices(@Devices[0], NumDevs, SDRPLAY_MAX_DEVICES), 'sdrplay_api_GetDevices') then begin
    sdrplay_api_Close();
    Exit;
  end;

  ChosenIdx := -1;
  for i := 0 to Integer(NumDevs) - 1 do
    if Devices[i].hwVer = SDRPLAY_RSP1A_ID then begin
      ChosenIdx := i;
      Break;
    end;
  if ChosenIdx < 0 then begin
    FLastError := 'no SDRplay RSP1A found (' + IntToStr(NumDevs) + ' other SDRplay device(s) present)';
    sdrplay_api_Close();
    Exit;
  end;

  FDeviceRec := Devices[ChosenIdx];
  if CallFailed(sdrplay_api_SelectDevice(@FDeviceRec), 'sdrplay_api_SelectDevice') then begin
    sdrplay_api_Close();
    Exit;
  end;
  FDeviceSelected := True;

  FDevParams := nil;
  if CallFailed(sdrplay_api_GetDeviceParams(FDeviceRec.dev, FDevParams), 'sdrplay_api_GetDeviceParams')
     or not Assigned(FDevParams) then begin
    sdrplay_api_ReleaseDevice(@FDeviceRec);
    FDeviceSelected := False;
    sdrplay_api_Close();
    Exit;
  end;

  FIsOpen := True;
  BuildCapabilities;

  // Push this unit's own default freq/rate/gain/AGC state into the live
  // device params now, so StartRX (and anyone reading Capabilities
  // meanwhile) sees consistent values - mirrors what the probe verified
  // works before calling Init.
  FDevParams^.devParams^.fsFreq.fsHz := FSampleRateHz;
  FDevParams^.rxChannelA^.tunerParams.rfFreq.rfHz := FCenterFreqHz;
  FDevParams^.rxChannelA^.tunerParams.bwType := CurrentBwType(FSampleRateHz);
  FDevParams^.rxChannelA^.tunerParams.ifType := sdrplay_api_IF_Zero;
  FDevParams^.rxChannelA^.tunerParams.gain.gRdB := 50;
  FDevParams^.rxChannelA^.tunerParams.gain.LNAstate := 0;
  FDevParams^.rxChannelA^.tunerParams.gain.minGr := sdrplay_api_NORMAL_MIN_GR;
  // AGC defaults ON (sdrplay_api_AGC_50HZ) - disabled here so this app's
  // own IF Gain Reduction control has real effect, not fought by the
  // API's own loop - see this unit's header comment (AGC).
  FDevParams^.rxChannelA^.ctrlParams.agc.enable := sdrplay_api_AGC_DISABLE;

  Result := True;
end;

procedure TSDRplayDevice.Close;
begin
  if FStreaming then StopRX;
  if FIsOpen then begin
    if FDeviceSelected then begin
      sdrplay_api_ReleaseDevice(@FDeviceRec);
      FDeviceSelected := False;
    end;
    sdrplay_api_Close();
    FDevParams := nil;
    FIsOpen := False;
  end;
end;

// Writes straight into the live DevParams struct always (so it's already
// correct whenever StartRX/the next Init happens); additionally pushes it
// to the device immediately via sdrplay_api_Update when already streaming
// - confirmed live-retune-safe by the probe.
function TSDRplayDevice.SetFrequencyHz(Hz: QWord): Boolean;
begin
  Result := False;
  if not FIsOpen then begin FLastError := 'device not open'; Exit; end;
  FDevParams^.rxChannelA^.tunerParams.rfFreq.rfHz := Hz;
  FCenterFreqHz := Hz;
  if FStreaming then begin
    if CallFailed(sdrplay_api_Update(FDeviceRec.dev, sdrplay_api_Tuner_A,
        sdrplay_api_Update_Tuner_Frf, sdrplay_api_Update_Ext1_None), 'sdrplay_api_Update(Frf)') then Exit;
  end;
  Result := True;
end;

// Also updates the matching analog filter (CurrentBwType) and, when the
// requested rate needs decimation, the decimation control block, in the
// same Update call when streaming - all three reasons are OR-able
// bitmask flags (see sdrplay_api_ReasonForUpdateT's own comment above).
// See this unit's own header comment (BELOW 2Msps (DECIMATION)) for the
// full rationale on the Hz<2.0e6 branch.
function TSDRplayDevice.SetSampleRateHz(Hz: Double): Boolean;
const
  s = 'TSDRplayDevice.SetSampleRateHz : ';
var
  AdcHz: Double;
  UpdateReason: sdrplay_api_ReasonForUpdateT;
begin
  Result := False;
  if not FIsOpen then begin FLastError := 'device not open'; Exit; end;

  UpdateReason := sdrplay_api_Update_Dev_Fs or sdrplay_api_Update_Tuner_BwType;
  if Hz < 2.0e6 then begin
    assert(Abs(Hz - 1.0e6) < 1.0, s + 'only the 1.0Msps decimated rate is currently supported below 2.0Msps');
    AdcHz := 2.0e6;
    FDevParams^.rxChannelA^.ctrlParams.decimation.enable := 1;
    FDevParams^.rxChannelA^.ctrlParams.decimation.decimationFactor := Round(AdcHz / Hz);
    FDevParams^.rxChannelA^.ctrlParams.decimation.wideBandSignal := 1;
    UpdateReason := UpdateReason or sdrplay_api_Update_Ctrl_Decimation;
  end else begin
    AdcHz := Hz;
    if FDevParams^.rxChannelA^.ctrlParams.decimation.enable <> 0 then begin
      // Coming back from a previously-decimated rate - explicitly turn
      // decimation back off rather than leaving it enabled with a
      // now-stale factor.
      FDevParams^.rxChannelA^.ctrlParams.decimation.enable := 0;
      FDevParams^.rxChannelA^.ctrlParams.decimation.decimationFactor := 1;
      FDevParams^.rxChannelA^.ctrlParams.decimation.wideBandSignal := 0;
      UpdateReason := UpdateReason or sdrplay_api_Update_Ctrl_Decimation;
    end;
  end;

  FDevParams^.devParams^.fsFreq.fsHz := AdcHz;
  FSampleRateHz := Hz;   // the EFFECTIVE (post-decimation) rate - what TryReadEpoch/SampleRateHz report
  FDevParams^.rxChannelA^.tunerParams.bwType := CurrentBwType(AdcHz);
  if FStreaming then begin
    if CallFailed(sdrplay_api_Update(FDeviceRec.dev, sdrplay_api_Tuner_A,
        UpdateReason, sdrplay_api_Update_Ext1_None),
        'sdrplay_api_Update(Fs+BwType+Decimation)') then Exit;
  end;
  Result := True;
end;

// StageIndex 0 (IF Gain Reduction) and 1 (LNA State) both live in the same
// sdrplay_api_GainT struct and are both applied via the same
// sdrplay_api_Update_Tuner_Gr reason (see this unit's header comment,
// GAIN MODEL). StageIndex 2 (RF Notch) is a DEVICE-level field
// (devParams^.rsp1aParams), not per-channel, unlike every other control
// here - still updated via sdrplay_api_Update with a TunerSelectT
// argument regardless (the API requires one; RSP1A is single-tuner, so
// Tuner_A is always correct here).
function TSDRplayDevice.SetGain(StageIndex: Integer; Value: Double): Boolean;
begin
  Result := False;
  if not FIsOpen then begin FLastError := 'device not open'; Exit; end;
  case StageIndex of
    0: begin
      FDevParams^.rxChannelA^.tunerParams.gain.gRdB := Round(Value);
      if FStreaming then
        Result := not CallFailed(sdrplay_api_Update(FDeviceRec.dev, sdrplay_api_Tuner_A,
          sdrplay_api_Update_Tuner_Gr, sdrplay_api_Update_Ext1_None), 'sdrplay_api_Update(Gr)')
      else
        Result := True;
    end;
    1: begin
      FDevParams^.rxChannelA^.tunerParams.gain.LNAstate := Byte(Round(Value));
      if FStreaming then
        Result := not CallFailed(sdrplay_api_Update(FDeviceRec.dev, sdrplay_api_Tuner_A,
          sdrplay_api_Update_Tuner_Gr, sdrplay_api_Update_Ext1_None), 'sdrplay_api_Update(Gr/LNAstate)')
      else
        Result := True;
    end;
    2: begin
      FDevParams^.devParams^.rsp1aParams.rfNotchEnable := Ord(Value <> 0);
      if FStreaming then
        Result := not CallFailed(sdrplay_api_Update(FDeviceRec.dev, sdrplay_api_Tuner_A,
          sdrplay_api_Update_Rsp1a_RfNotchControl, sdrplay_api_Update_Ext1_None), 'sdrplay_api_Update(RfNotch)')
      else
        Result := True;
    end;
  else
    FLastError := 'unknown gain stage ' + IntToStr(StageIndex);
  end;
end;

function TSDRplayDevice.SetBoolOption(OptionIndex: Integer; Value: Boolean): Boolean;
begin
  Result := False;
  if not FIsOpen then begin FLastError := 'device not open'; Exit; end;
  case OptionIndex of
    0: begin
      FDevParams^.rxChannelA^.rsp1aTunerParams.biasTEnable := Ord(Value);
      if FStreaming then
        Result := not CallFailed(sdrplay_api_Update(FDeviceRec.dev, sdrplay_api_Tuner_A,
          sdrplay_api_Update_Rsp1a_BiasTControl, sdrplay_api_Update_Ext1_None), 'sdrplay_api_Update(BiasT)')
      else
        Result := True;
    end;
  else
    FLastError := 'unknown bool option ' + IntToStr(OptionIndex);
  end;
end;

function TSDRplayDevice.StartRX: Boolean;
var
  CBFns: sdrplay_api_CallbackFnsT;
begin
  Result := False;
  if not FIsOpen then begin FLastError := 'device not open'; Exit; end;
  if FStreaming then begin Result := True; Exit; end;

  FRing.Reset;

  CBFns.StreamACbFn := @SDRplayStreamCallback;
  CBFns.StreamBCbFn := nil;   // single-tuner RSP1A - no B channel
  CBFns.EventCbFn := @SDRplayEventCallback;

  if CallFailed(sdrplay_api_Init(FDeviceRec.dev, CBFns, Pointer(Self)), 'sdrplay_api_Init') then Exit;

  FStreaming := True;
  Result := True;
end;

function TSDRplayDevice.StopRX: Boolean;
begin
  Result := True;
  if not FStreaming then Exit;
  Result := not CallFailed(sdrplay_api_Uninit(FDeviceRec.dev), 'sdrplay_api_Uninit');
  FStreaming := False;
end;

// Interleaves the callback's two separate 16-bit I/Q arrays into one
// (I0,Q0,I1,Q1,...) SmallInt buffer before handing the bytes to the ring -
// see this unit's header comment (SAMPLE FORMAT) for why this step exists
// at all, unlike either sibling backend.
procedure TSDRplayDevice.OnRawData(xi, xq: PSmallInt; NumSamples: Integer);
var
  Interleaved: array of SmallInt;
  i: Integer;
begin
  if NumSamples <= 0 then Exit;
  SetLength(Interleaved, NumSamples * 2);
  for i := 0 to NumSamples - 1 do begin
    Interleaved[i * 2] := xi[i];
    Interleaved[i * 2 + 1] := xq[i];
  end;
  FRing.Write(PByte(@Interleaved[0]), NumSamples * 2 * SizeOf(SmallInt));
end;

function TSDRplayDevice.TryReadEpoch(N: Integer; out IQ: TVMobjZ): Boolean;
const
  s = 'TSDRplayDevice.TryReadEpoch : ';
var
  Tmp: TSDRByteArray;
  Samples: PSmallInt;
  i: Integer;
begin
  assert(N > 0, s + 'N must be positive');
  Result := False;
  // 2 components (I,Q) * 2 bytes (SmallInt) per complex sample.
  if not FRing.TryReadNewest(N * 4, Tmp) then Exit;

  // Signed 16-bit interleaved I/Q (see OnRawData above) - normalised to
  // roughly [-1,1) the same way as the other two backends' own sample
  // widths, just against a 16-bit rather than 8-bit full scale.
  Samples := PSmallInt(@Tmp[0]);
  IQ := TVMobjZ.Create(1, N);
  for i := 0 to N - 1 do
    IQ[0, i] := Cplx(Samples[i * 2] / 32768.0, Samples[i * 2 + 1] / 32768.0);

  CorrectIQEpoch(IQ);
  Result := True;
end;

initialization
  SDRplayLibLoaded := InitializeSDRplayLib;

finalization
  if SDRplayHandle <> NilHandle then UnloadLibrary(SDRplayHandle);

end.
