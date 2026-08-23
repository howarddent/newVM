unit uSDRAudioIPC;

{*******************************************************************************

     Shared wire format between uWaveOutPlayer.pas's Darwin backend (the
     PARENT - the main SDR_Radio process, which streams from a live HackRF)
     and sdraudiohelper.lpr (the CHILD - a small standalone console program
     that owns the actual CoreAudio AudioQueue and does nothing else).

     WHY THIS SPLIT EXISTS: confirmed by a standalone bare-console
     reproduction (no LCL/GUI involved at all) that loading AudioToolbox -
     by ANY means, static linkframework directive or a plain runtime dlopen,
     before or after streaming starts - drops libhackrf's native USB
     transfer callback delivery from ~98% success to 0%, in-process, on
     this machine. AudioToolbox and libhackrf/libusb cannot coexist in one
     process here. The fix is architectural, not a code-level workaround:
     move every AudioToolbox call into its own child process that never
     touches the HackRF, and have the main process (which owns the HackRF
     and must stay AudioToolbox-free) feed it PCM over a pipe instead of
     calling CoreAudio directly. See uWaveOutPlayer.pas's own header
     comment (macOS BACKEND) for the parent side, and sdraudiohelper.lpr
     for the child side.

     PROTOCOL (parent writes to the child's stdin; the child never writes
     anything back - one-directional is sufficient, since the parent has
     no need to know per-buffer completion, only whether the child is
     still alive, which a failed pipe write already reveals):
       1. Exactly one THeader, first thing, giving the format and the
          per-frame size ceiling the child should pre-allocate its
          AudioQueue buffers to.
       2. Any number of frames, each a LongWord byte count followed by
          exactly that many bytes of interleaved 16-bit signed PCM
          (already tanh-soft-limited and scaled by the parent - the child
          does no audio math of its own, purely a CoreAudio conduit).
       3. The parent closes its end of the pipe (TProcess.CloseInput) to
          signal end of stream; the child treats EOF on stdin as "stop
          and exit cleanly", not an error.
     A frame's byte count is always a whole number of stereo sample pairs
     (a multiple of 4) and never exceeds THeader.MaxSamplesPerChannel*4 -
     enforced by the parent, trusted (not re-validated) by the child,
     since both ends are built from this same unit and only ever talk to
     each other.

*******************************************************************************}

{$mode objfpc}{$H+}

interface

const
  // Arbitrary sentinel, just enough to catch "wrong program/version talking
  // to the wrong end of this pipe" during development - not a real
  // versioned protocol, since parent and child are always built and
  // shipped together from this same repo.
  SDRAudioIPCMagic = LongWord($53445241); // 'SDRA'

type
  TSDRAudioIPCHeader = packed record
    Magic: LongWord;
    SampleRateHz: LongWord;
    MaxSamplesPerChannel: LongWord;
    BufferCount: LongWord;
  end;

implementation

end.
