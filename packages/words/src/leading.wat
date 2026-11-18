(module
  (import "./memory.wat")
  (import "./types.wat")
  (import "./scan.wat")
  (import "./out.wat")
  (import "./record.wat")
  (import "./inline.wat")

  ;; The leadingWhitespace option (control bytes 34-35): put back the spaces
  ;; and tabs typed at the start of a paragraph line past its containers'
  ;; structure, which CommonMark drops, as
  ;; `<span data-leading-whitespace="">WS</span>`. Only HTML paragraphs
  ;; outside footnotes take it. Block analysis is unchanged: each line's
  ;; container markers are matched again from the source when it renders.
  ;;
  ;; $lw is 0 when off, else 1 + the columns every line is already indented.
  (global $lw (mut i32) (i32.const 0))
  (global $lwActive (mut i32) (i32.const 0))
  ;; the paragraph being rendered, or 0
  (global $lwRec (mut i32) (i32.const 0))
  ;; the last container opener rendered
  (global $lwOpener (mut i32) (i32.const 0))
  ;; container-end cursor: offset, column, and whether the byte at the offset
  ;; is a tab whose first columns are taken
  (global $lwOff (mut i32) (i32.const 0))
  (global $lwCol (mut i32) (i32.const 0))
  (global $lwTab (mut i32) (i32.const 0))
  (global $lwEnd (mut i32) (i32.const 0))

  ;; Per render level: [0] the opener record, [4] an item's continuation
  ;; indent (-2 unknown, -1 none).
  (func $lwAt (param $level i32) (result i32)
    (i32.add (i32.const $mem.lwChain) (i32.shl (local.get $level) (i32.const 3))))

  (func $lwPush (param $level i32) (param $r i32)
    (i32.store (call $lwAt (local.get $level)) (local.get $r))
    (i32.store offset=4 (call $lwAt (local.get $level)) (i32.const -2))
    (global.set $lwOpener (local.get $r)))

  (func $lwTabStop (param $col i32) (result i32)
    (i32.add (i32.and (local.get $col) (i32.const -4)) (i32.const 4)))

  (func $lwLineStart (param $p i32) (result i32)
    (local $c i32)
    (block $done
      (loop $back
        (br_if $done (i32.le_u (local.get $p) (i32.const $mem.input)))
        (local.set $c (i32.load8_u (i32.sub (local.get $p) (i32.const 1))))
        (br_if $done (i32.or (i32.eq (local.get $c) (i32.const 10))
          (i32.eq (local.get $c) (i32.const 13))))
        (local.set $p (i32.sub (local.get $p) (i32.const 1)))
        (br $back)))
    (if (i32.and (i32.eq (local.get $p) (i32.const $mem.input))
          (i32.eq (i32.and (i32.load (local.get $p)) (i32.const 0xffffff))
            (i32.const "\ef\bb\bf")))
      (then (local.set $p (i32.add (local.get $p) (i32.const 3)))))
    (local.get $p))

  ;; Move the cursor $width columns through spaces and tabs, splitting a tab
  ;; where it must. Returns 0 at any other byte.
  (func $lwSkip (param $width i32) (result i32)
    (local $c i32)
    (local $step i32)
    (block $done
      (loop $l
        (br_if $done (i32.le_s (local.get $width) (i32.const 0)))
        (local.set $c (i32.load8_u (global.get $lwOff)))
        (if (i32.eqz (call $isSpaceByte (local.get $c))) (then (return (i32.const 0))))
        (local.set $step (select (i32.const 1)
          (i32.sub (call $lwTabStop (global.get $lwCol)) (global.get $lwCol))
          (i32.eq (local.get $c) (i32.const 32))))
        (if (i32.gt_u (local.get $step) (local.get $width))
          (then
            (global.set $lwCol (i32.add (global.get $lwCol) (local.get $width)))
            (global.set $lwTab (i32.const 1))
            (return (i32.const 1))))
        (global.set $lwOff (i32.add (global.get $lwOff) (i32.const 1)))
        (global.set $lwCol (i32.add (global.get $lwCol) (local.get $step)))
        (global.set $lwTab (i32.const 0))
        (local.set $width (i32.sub (local.get $width) (local.get $step)))
        (br $l)))
    (i32.const 1))

  ;; Set the cursor where item $r's content starts on its own first line,
  ;; measured from the marker as CommonMark does.
  (func $lwItemContent (param $r i32)
    (local $m i32)
    (local $p i32)
    (local $line i32)
    (local $col i32)
    (local $c i32)
    (local $markCol i32)
    (local.set $m (i32.load offset=8 (local.get $r)))
    (local.set $line (call $lwLineStart (local.get $m)))
    (local.set $c (i32.load8_u (local.get $m)))
    (local.set $p (i32.add (local.get $m) (i32.const 1)))
    (if (i32.lt_u (i32.sub (local.get $c) (i32.const 48)) (i32.const 10))
      (then
        (loop $digits
          (local.set $c (i32.load8_u (local.get $p)))
          (local.set $p (i32.add (local.get $p) (i32.const 1)))
          (br_if $digits (i32.lt_u (i32.sub (local.get $c) (i32.const 48)) (i32.const 10))))))
    ;; the column of the marker's end
    (local.set $c (local.get $line))
    (block $counted
      (loop $count
        (br_if $counted (i32.ge_u (local.get $c) (local.get $p)))
        (local.set $col (select (call $lwTabStop (local.get $col))
          (i32.add (local.get $col) (i32.const 1))
          (i32.eq (i32.load8_u (local.get $c)) (i32.const 9))))
        (local.set $c (i32.add (local.get $c) (i32.const 1)))
        (br $count)))
    (local.set $markCol (local.get $col))
    (local.set $m (local.get $p))
    (block $spaced
      (loop $space
        (local.set $c (i32.load8_u (local.get $m)))
        (br_if $spaced (i32.eqz (call $isSpaceByte (local.get $c))))
        (local.set $col (select (call $lwTabStop (local.get $col))
          (i32.add (local.get $col) (i32.const 1))
          (i32.eq (local.get $c) (i32.const 9))))
        (local.set $m (i32.add (local.get $m) (i32.const 1)))
        (br $space)))
    (global.set $lwOff (local.get $p))
    (global.set $lwCol (local.get $markCol))
    (global.set $lwTab (i32.const 0))
    ;; a blank first line, or code after five or more columns, starts one
    ;; column past the marker
    (if (i32.or (i32.or (i32.eq (local.get $c) (i32.const 10)) (i32.eq (local.get $c) (i32.const 13)))
          (i32.ge_u (local.get $m) (global.get $eof)))
      (then
        (global.set $lwCol (i32.add (local.get $markCol) (i32.const 1)))
        (return)))
    (if (i32.le_u (i32.sub (local.get $col) (local.get $markCol)) (i32.const 4))
      (then
        (global.set $lwOff (local.get $m))
        (global.set $lwCol (local.get $col))
        (return)))
    (drop (call $lwSkip (i32.const 1))))

  ;; The columns item level $level's continuation lines need past its
  ;; parent's markers, or -1.
  (func $lwItemIndent (param $level i32) (result i32)
    (local $at i32)
    (local $r i32)
    (local $parent i32)
    (local.set $at (call $lwAt (local.get $level)))
    (if (i32.ne (i32.load offset=4 (local.get $at)) (i32.const -2))
      (then (return (i32.load offset=4 (local.get $at)))))
    (local.set $r (i32.load (local.get $at)))
    (local.set $parent (i32.const -1))
    (if (call $lwContainerEnd
          (call $lwLineStart (i32.load offset=8 (local.get $r))) (local.get $level))
      (then
        (local.set $parent (global.get $lwCol))
        (call $lwItemContent (local.get $r))
        (local.set $parent (i32.sub (global.get $lwCol) (local.get $parent)))))
    (i32.store offset=4 (local.get $at) (local.get $parent))
    (local.get $parent))

  ;; Set the cursor past the markers and indentation of the first $depth
  ;; render levels on the line starting at $line. Returns 0 for a lazy line.
  (func $lwContainerEnd (param $line i32) (param $depth i32) (result i32)
    (local $i i32)
    (local $t i32)
    (local $r i32)
    (local $n i32)
    (local $start i32)
    ;; item indents first: working them out moves the cursor
    (block $known
      (loop $l
        (br_if $known (i32.ge_u (local.get $i) (local.get $depth)))
        (if (i32.eq (i32.load8_u (call $rsAt (local.get $i))) (enum.get $Blk.li))
          (then (drop (call $lwItemIndent (local.get $i)))))
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $l)))
    (global.set $lwOff (local.get $line))
    (global.set $lwCol (i32.const 0))
    (global.set $lwTab (i32.const 0))
    (if (i32.eqz (call $lwSkip (i32.sub (global.get $lw) (i32.const 1))))
      (then (return (i32.const 0))))
    (local.set $i (i32.const 0))
    (block $done
      (loop $l
        (br_if $done (i32.ge_u (local.get $i) (local.get $depth)))
        (local.set $t (i32.load8_u (call $rsAt (local.get $i))))
        (if (i32.eq (local.get $t) (enum.get $Blk.quote))
          (then
            ;; up to three columns of indentation, the marker, then one optional space
            (local.set $start (global.get $lwCol))
            (block $indented
              (loop $space
                (br_if $indented (i32.eqz (call $isSpaceByte (i32.load8_u (global.get $lwOff)))))
                (drop (call $lwSkip (i32.const 1)))
                (if (i32.gt_s (i32.sub (global.get $lwCol) (local.get $start)) (i32.const 3))
                  (then (return (i32.const 0))))
                (br $space)))
            (if (i32.or (global.get $lwTab)
                  (i32.ne (i32.load8_u (global.get $lwOff)) (i32.const 62)))
              (then (return (i32.const 0))))
            (global.set $lwOff (i32.add (global.get $lwOff) (i32.const 1)))
            (global.set $lwCol (i32.add (global.get $lwCol) (i32.const 1)))
            (if (call $isSpaceByte (i32.load8_u (global.get $lwOff)))
              (then (drop (call $lwSkip (i32.const 1)))))))
        (if (i32.eq (local.get $t) (enum.get $Blk.li))
          (then
            (local.set $r (i32.load (call $lwAt (local.get $i))))
            (if (i32.eq (call $lwLineStart (i32.load offset=8 (local.get $r))) (local.get $line))
              (then (call $lwItemContent (local.get $r)))
              (else
                (local.set $n (i32.load offset=4 (call $lwAt (local.get $i))))
                (if (i32.or (i32.lt_s (local.get $n) (i32.const 0))
                      (i32.eqz (call $lwSkip (local.get $n))))
                  (then (return (i32.const 0))))))))
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $l)))
    (i32.const 1))

  ;; Whether the content at offset $p renders starting with a space, tab or
  ;; line ending, or with a line break. $i is a mark index at or before $p.
  (func $lwBlankAt (param $p i32) (param $i i32) (result i32)
    (local $m i32)
    (local $t i32)
    (local $c i32)
    (local $b i32)
    (local $e i32)
    (local $q i32)
    (loop $at
      (if (i32.ge_u (local.get $p) (global.get $contentLen)) (then (return (i32.const 1))))
      (block $noMark
        (loop $find
          (br_if $noMark (i32.ge_u (local.get $i) (global.get $nSlots)))
          (local.set $m (call $slotAt (local.get $i)))
          (local.set $b (i32.load offset=$M.beg (local.get $m)))
          (if (i32.lt_u (local.get $b) (local.get $p))
            (then
              (local.set $i (i32.add (local.get $i) (i32.const 1)))
              (br $find))))
        (br_if $noMark (i32.ne (local.get $b) (local.get $p)))
        (local.set $t (i32.load8_u offset=$M.type (local.get $m)))
        (local.set $e (i32.load offset=$M.end (local.get $m)))
        (if (i32.or (i32.eq (local.get $t) (enum.get $Mk.softbreak))
              (i32.eq (local.get $t) (enum.get $Mk.hardbreak)))
          (then (return (i32.const 1))))
        (if (i32.eq (local.get $t) (enum.get $Mk.entity))
          (then
            (local.set $c (i32.load offset=$M.data (local.get $m)))
            (return (i32.or (call $isSpaceByte (local.get $c))
              (i32.or (i32.eq (local.get $c) (i32.const 10)) (i32.eq (local.get $c) (i32.const 13)))))))
        (if (i32.eq (local.get $t) (enum.get $Mk.code))
          (then
            ;; the content sits inside equal backtick runs; one space strips
            ;; from both sides unless all of it is spaces or line endings
            (local.set $q (i32.load offset=$M.data (local.get $m)))
            (local.set $e (i32.sub (local.get $e) (i32.sub (local.get $q) (local.get $b))))
            (if (i32.ge_u (local.get $q) (local.get $e)) (then (return (i32.const 0))))
            (local.set $c (i32.load8_u (call $contentAt (local.get $q))))
            (if (i32.and (i32.ne (local.get $c) (i32.const 32)) (i32.ne (local.get $c) (i32.const 10)))
              (then (return (i32.const 0))))
            (if (i32.lt_u (i32.sub (local.get $e) (local.get $q)) (i32.const 2))
              (then (return (i32.const 1))))
            (local.set $c (i32.load8_u (call $contentAt (i32.sub (local.get $e) (i32.const 1)))))
            (if (i32.and (i32.ne (local.get $c) (i32.const 32)) (i32.ne (local.get $c) (i32.const 10)))
              (then (return (i32.const 1))))
            (local.set $c (i32.load8_u (call $contentAt (i32.add (local.get $q) (i32.const 1)))))
            (return (i32.or (i32.or (i32.eq (local.get $c) (i32.const 32)) (i32.eq (local.get $c) (i32.const 10)))
              (i32.eqz (call $lwHasText (i32.add (local.get $q) (i32.const 1)) (local.get $e)))))))
        ;; a link's text, or emphasis whose delimiters all open tags, is
        ;; followed by what starts it
        (if (i32.eq (local.get $t) (enum.get $Mk.linkopen))
          (then
            (if (i32.and (i32.load8_u offset=$M.flags
                  (call $slotAt (i32.load offset=$M.data (local.get $m)))) (i32.const $MF.image))
              (then (return (i32.const 0))))
            (local.set $p (local.get $e))
            (local.set $i (i32.add (local.get $i) (i32.const 1)))
            (br $at)))
        (if (i32.and (i32.eq (local.get $t) (enum.get $Mk.emph))
              (i32.eqz (i32.load offset=$M.rem (local.get $m))))
          (then
            (local.set $p (local.get $e))
            (local.set $i (i32.add (local.get $i) (i32.const 1)))
            (br $at)))
        (return (i32.const 0)))
      (local.set $c (i32.load8_u (call $contentAt (local.get $p))))
      (return (i32.or (call $isSpaceByte (local.get $c))
        (i32.or (i32.eq (local.get $c) (i32.const 10)) (i32.eq (local.get $c) (i32.const 13))))))
    (i32.const 0))

  ;; whether content [$p, $e) holds a byte other than a space or line ending
  (func $lwHasText (param $p i32) (param $e i32) (result i32)
    (local $c i32)
    (block $done
      (loop $l
        (br_if $done (i32.ge_u (local.get $p) (local.get $e)))
        (local.set $c (i32.load8_u (call $contentAt (local.get $p))))
        (if (i32.and (i32.ne (local.get $c) (i32.const 32)) (i32.ne (local.get $c) (i32.const 10)))
          (then (return (i32.const 1))))
        (local.set $p (i32.add (local.get $p) (i32.const 1)))
        (br $l)))
    (i32.const 0))

  ;; the input address of content offset $p of the current paragraph
  (func $lwSource (param $p i32) (result i32)
    (local $n i32)
    (local $i i32)
    (local $line i32)
    (local $start i32)
    (local $len i32)
    (if (i32.lt_u (global.get $contentBase) (global.get $eof))
      (then (return (i32.add (global.get $contentBase) (local.get $p)))))
    (local.set $n (i32.load offset=$R.nLines (global.get $lwRec)))
    (loop $l
      (local.set $line (call $lineAt (global.get $lwRec) (local.get $i)))
      (local.set $len (i32.sub (call $lineEndOf (local.get $line)) (call $lineBeg (local.get $line))))
      (if (i32.or (i32.le_u (local.get $p) (i32.add (local.get $start) (local.get $len)))
            (i32.ge_u (i32.add (local.get $i) (i32.const 1)) (local.get $n)))
        (then (return (i32.add (call $lineBeg (local.get $line))
          (i32.sub (local.get $p) (local.get $start))))))
      (local.set $start (i32.add (local.get $start) (i32.add (local.get $len) (i32.const 1))))
      (local.set $i (i32.add (local.get $i) (i32.const 1)))
      (br $l))
    (i32.const 0))

  ;; Whether whitespace was typed before the line content at input address
  ;; $s, past the containers. Leaves the cursor at its start and $lwEnd at $s.
  (func $lwTyped (param $s i32) (result i32)
    (local $p i32)
    (if (i32.eqz (call $lwContainerEnd (call $lwLineStart (local.get $s)) (global.get $rsp)))
      (then (return (i32.const 0))))
    (if (i32.ge_u (global.get $lwOff) (local.get $s)) (then (return (i32.const 0))))
    (local.set $p (global.get $lwOff))
    (block $blank
      (loop $l
        (br_if $blank (i32.ge_u (local.get $p) (local.get $s)))
        (if (i32.eqz (call $isSpaceByte (i32.load8_u (local.get $p)))) (then (return (i32.const 0))))
        (local.set $p (i32.add (local.get $p) (i32.const 1)))
        (br $l)))
    (global.set $lwEnd (local.get $s))
    (i32.const 1))

  ;; Write the whitespace $lwTyped found.
  (func $lwWrite
    (local $p i32)
    (local $n i32)
    (out.str "<span data-leading-whitespace=\22\22>")
    (local.set $p (global.get $lwOff))
    ;; a tab split by the containers keeps the columns left of it, as spaces
    (if (global.get $lwTab)
      (then
        (local.set $n (i32.sub (call $lwTabStop (global.get $lwCol)) (global.get $lwCol)))
        (call $ensureOut (local.get $n))
        (memory.fill (global.get $out) (i32.const 32) (local.get $n))
        (global.set $out (i32.add (global.get $out) (local.get $n)))
        (local.set $p (i32.add (local.get $p) (i32.const 1)))))
    (call $outCopy (local.get $p) (global.get $lwEnd))
    (out.str "</span>"))

  ;; after a line break mark that $lwPrepareBreak flagged
  (func $lwBreak (param $s i32)
    (drop (call $lwTyped (local.get $s)))
    (call $lwWrite))

  ;; GitHub's alert marker line: `[!NOTE]` and the like, alone on the line
  (func $lwAlertLine (result i32)
    (local $p i32)
    (local $e i32)
    (local $n i32)
    (local $c i32)
    (local $w i64)
    (local.set $p (global.get $contentBase))
    (local.set $e (i32.add (local.get $p) (global.get $contentLen)))
    (if (i32.lt_u (global.get $contentLen) (i32.const 6)) (then (return (i32.const 0))))
    (if (i32.ne (i32.load16_u (local.get $p)) (i32.const "[!")) (then (return (i32.const 0))))
    (local.set $p (i32.add (local.get $p) (i32.const 2)))
    (block $word
      (loop $l
        (br_if $word (i32.ge_u (i32.add (local.get $p) (local.get $n)) (local.get $e)))
        (local.set $c (i32.or (i32.load8_u (i32.add (local.get $p) (local.get $n))) (i32.const 32)))
        (br_if $word (i32.ge_u (i32.sub (local.get $c) (i32.const 97)) (i32.const 26)))
        (local.set $n (i32.add (local.get $n) (i32.const 1)))
        (br $l)))
    (local.set $w (i64.or (i64.load (local.get $p)) (i64.const 0x2020202020202020)))
    (local.set $c (i32.or (i32.or
      (i32.and (i32.eq (local.get $n) (i32.const 4))
        (i64.eq (i64.and (local.get $w) (i64.const 0xffffffff)) (i64.const "note")))
      (i32.and (i32.eq (local.get $n) (i32.const 3))
        (i64.eq (i64.and (local.get $w) (i64.const 0xffffff)) (i64.const "tip"))))
      (i32.or
        (i32.and (i32.eq (local.get $n) (i32.const 7))
          (i32.or
            (i64.eq (i64.and (local.get $w) (i64.const 0xffffffffffffff)) (i64.const "warning"))
            (i64.eq (i64.and (local.get $w) (i64.const 0xffffffffffffff)) (i64.const "caution"))))
        (i32.and (i32.eq (local.get $n) (i32.const 9))
          (i32.and (i64.eq (local.get $w) (i64.const "importan"))
            (i32.eq (i32.or (i32.load8_u offset=8 (local.get $p)) (i32.const 32)) (i32.const 116)))))))
    (if (i32.eqz (local.get $c))
      (then (return (i32.const 0))))
    (local.set $p (i32.add (local.get $p) (local.get $n)))
    (if (i32.ne (i32.load8_u (local.get $p)) (i32.const 93)) (then (return (i32.const 0))))
    (local.set $p (i32.add (local.get $p) (i32.const 1)))
    (if (i32.ge_u (local.get $p) (local.get $e)) (then (return (i32.const 1))))
    (local.set $c (i32.load8_u (local.get $p)))
    (i32.or (i32.eq (local.get $c) (i32.const 10))
      (i32.and (i32.eq (local.get $c) (i32.const 13))
        (i32.eq (i32.load8_u offset=1 (local.get $p)) (i32.const 10)))))

  ;; Start paragraph $r (other leaves are skipped) and write its first line's
  ;; whitespace. $literal: the content is literal text, with no marks.
  (func $lwParagraph (param $r i32) (param $literal i32)
    (local $o i32)
    (local $i i32)
    (local $t i32)
    (global.set $lwRec (i32.const 0))
    (if (i32.ne (i32.load8_u (local.get $r)) (enum.get $Blk.p)) (then (return)))
    (global.set $lwRec (local.get $r))
    (if (i32.eqz (local.get $literal))
      (then
        (block $done
          (loop $l
            (br_if $done (i32.ge_u (local.get $i) (global.get $nSlots)))
            (local.set $t (i32.load8_u offset=$M.type (call $slotAt (local.get $i))))
            (if (i32.or (i32.eq (local.get $t) (enum.get $Mk.softbreak))
                  (i32.eq (local.get $t) (enum.get $Mk.hardbreak)))
              (then (call $lwPrepareBreak (local.get $i))))
            (local.set $i (i32.add (local.get $i) (i32.const 1)))
            (br $l)))))
    ;; the alerts plugin drops the marker's line of a quote's first paragraph
    (local.set $o (global.get $lwOpener))
    (if (i32.and
          (i32.and (i32.ne (local.get $o) (i32.const 0))
            (i32.eq (i32.load8_u (local.get $o)) (enum.get $Blk.quote)))
          (i32.eq (i32.add (local.get $o) (i32.load offset=4 (local.get $o))) (local.get $r)))
      (then (if (call $lwAlertLine) (then (return)))))
    (if (i32.eqz (local.get $literal))
      (then (if (call $lwBlankAt (i32.const 0) (i32.const 0)) (then (return)))))
    (if (call $lwTyped (call $lwSource (i32.const 0)))
      (then (call $lwWrite))))

  ;; the first mark at or after $i that starts at or after $p
  (func $lwMarkFrom (param $i i32) (param $p i32) (result i32)
    (block $done
      (loop $l
        (br_if $done (i32.ge_u (local.get $i) (global.get $nSlots)))
        (br_if $done (i32.ge_u (i32.load offset=$M.beg (call $slotAt (local.get $i))) (local.get $p)))
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $l)))
    (local.get $i))

  ;; The end of the spaces and tabs at content offset $p, typed or written as
  ;; character references, from mark $i on.
  (func $lwTrimText (param $p i32) (param $i i32) (result i32)
    (local $m i32)
    (local $c i32)
    (loop $l
      (local.set $i (call $lwMarkFrom (local.get $i) (local.get $p)))
      (if (i32.ge_u (local.get $p) (global.get $contentLen)) (then (return (local.get $p))))
      (if (i32.lt_u (local.get $i) (global.get $nSlots))
        (then
          (local.set $m (call $slotAt (local.get $i)))
          (if (i32.eq (i32.load offset=$M.beg (local.get $m)) (local.get $p))
            (then
              (if (i32.and (i32.eq (i32.load8_u offset=$M.type (local.get $m)) (enum.get $Mk.entity))
                    (call $isSpaceByte (i32.load offset=$M.data (local.get $m))))
                (then
                  (local.set $p (i32.load offset=$M.end (local.get $m)))
                  (br $l)))
              (return (local.get $p))))))
      (if (call $isSpaceByte (i32.load8_u (call $contentAt (local.get $p))))
        (then
          (local.set $p (i32.add (local.get $p) (i32.const 1)))
          (br $l))))
    (local.get $p))

  ;; Whether the content at $p starts with text: a byte or a character reference.
  (func $lwTextAt (param $p i32) (param $i i32) (result i32)
    (local $m i32)
    (if (i32.ge_u (local.get $p) (global.get $contentLen)) (then (return (i32.const 0))))
    (local.set $i (call $lwMarkFrom (local.get $i) (local.get $p)))
    (if (i32.ge_u (local.get $i) (global.get $nSlots)) (then (return (i32.const 1))))
    (local.set $m (call $slotAt (local.get $i)))
    (i32.or (i32.ne (i32.load offset=$M.beg (local.get $m)) (local.get $p))
      (i32.or (i32.eq (i32.load8_u offset=$M.type (local.get $m)) (enum.get $Mk.entity))
        (i32.eq (i32.load8_u offset=$M.type (local.get $m)) (enum.get $Mk.escape)))))

  ;; Decide the span after line break mark $i. Converting to HTML trims the
  ;; start of what follows a line break; the span takes the break's place, so
  ;; the content after it gets the same trim: spaces and tabs of text, a code
  ;; span's leading blanks, and the text that starts emphasis or a link. The
  ;; break mark keeps the line's input address in its data and flag 64.
  (func $lwPrepareBreak (param $i i32)
    (local $m i32)
    (local $e i32)
    (local $s i32)
    (local $j i32)
    (local $n i32)
    (local $t i32)
    (local $q i32)
    (local $head i32)
    (local.set $m (call $slotAt (local.get $i)))
    (local.set $e (i32.load offset=$M.end (local.get $m)))
    (if (i32.ge_u (local.get $e) (global.get $contentLen)) (then (return)))
    (local.set $s (call $lwSource (local.get $e)))
    (if (i32.eqz (call $lwTyped (local.get $s))) (then (return)))
    (local.set $j (call $lwMarkFrom (i32.add (local.get $i) (i32.const 1)) (local.get $e)))
    (local.set $t (i32.const -1))
    (if (i32.lt_u (local.get $j) (global.get $nSlots))
      (then
        (local.set $n (call $slotAt (local.get $j)))
        (if (i32.eq (i32.load offset=$M.beg (local.get $n)) (local.get $e))
          (then (local.set $t (i32.load8_u offset=$M.type (local.get $n)))))))
    (block $decided
      ;; a code span
      (if (i32.eq (local.get $t) (enum.get $Mk.code))
        (then
          (i32.store offset=$M.rem (local.get $n) (i32.const 1))
          (br $decided)))
      ;; emphasis that opens one tag, or an inline link, starting with text
      (local.set $q (i32.const 0))
      (if (i32.eq (local.get $t) (enum.get $Mk.emph))
        (then
          (local.set $head (i32.load offset=$M.openHead (local.get $n)))
          (if (i32.and (i32.eqz (i32.load offset=$M.rem (local.get $n))) (i32.ne (local.get $head) (i32.const 0)))
            (then (local.set $q (i32.eqz (i32.and (i32.load (call $tagAt (local.get $head)))
              (i32.const $T.nextMask))))))))
      (if (i32.eq (local.get $t) (enum.get $Mk.linkopen))
        (then
          (local.set $head (call $slotAt (i32.load offset=$M.data (local.get $n))))
          (local.set $q (i32.eqz (i32.or
            (i32.and (i32.load8_u offset=$M.flags (local.get $head)) (i32.const $MF.image))
            (i32.load offset=$L.def (local.get $head)))))))
      (if (local.get $q)
        (then
          (local.set $q (i32.load offset=$M.end (local.get $n)))
          (if (call $lwTextAt (local.get $q) (i32.add (local.get $j) (i32.const 1)))
            (then
              (local.set $q (call $lwTrimText (local.get $q) (i32.add (local.get $j) (i32.const 1))))
              (i32.store offset=$M.end (call $slotAt (local.get $j)) (local.get $q))
              (br $decided)))
          (br_if $decided (i32.eqz (call $lwBlankAt (local.get $e) (local.get $j))))
          (return)))
      ;; text
      (local.set $q (call $lwTrimText (local.get $e) (local.get $j)))
      (if (call $lwBlankAt (local.get $q) (local.get $j)) (then (return)))
      (i32.store offset=$M.end (local.get $m) (local.get $q)))
    (i32.store offset=$M.data (local.get $m) (local.get $s))
    (i32.store8 offset=$M.flags (local.get $m)
      (i32.or (i32.load8_u offset=$M.flags (local.get $m)) (i32.const 64))))

  ;; a flagged code span's content start, past its leading blanks
  (func $lwTrimCode (param $b i32) (param $e i32) (result i32)
    (local $c i32)
    (block $done
      (loop $l
        (br_if $done (i32.ge_u (local.get $b) (local.get $e)))
        (local.set $c (i32.load8_u (call $contentAt (local.get $b))))
        (br_if $done (i32.eqz (i32.or (call $isSpaceByte (local.get $c))
          (i32.or (i32.eq (local.get $c) (i32.const 10)) (i32.eq (local.get $c) (i32.const 13))))))
        (local.set $b (i32.add (local.get $b) (i32.const 1)))
        (br $l)))
    (local.get $b))
)
