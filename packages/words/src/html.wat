(module
  (import "./memory.wat")
  (import "./types.wat")
  (import "./scan.wat")
  (import "./out.wat")
  (import "./record.wat")
  (import "./htmlscan.wat")
  (import "./entity.wat")
  (import "./render.wat")

  (global $incompleteCodeRec (mut i32) (i32.const 0))

  ;; start a new output line unless one has just started, matching the
  ;; reference renderer's `cr()`
  (func $cr
    (if (i32.le_u (global.get $out) (global.get $outBase)) (then (return)))
    (if (i32.ne (i32.load8_u (i32.sub (global.get $out) (i32.const 1))) (i32.const 10))
      (then (call $outByte (i32.const 10)))))

  (func $htmlBlockOpen (param $t i32) (param $r i32)
    (call $cr)
    (if (i32.eq (local.get $t) (enum.get $Blk.quote))
      (then
        (out.str "<blockquote>\n")
        (if (global.get $fmt) (then (call $mark (i32.const 10) (i32.const 1))))
        (return)))
    (if (i32.eq (local.get $t) (enum.get $Blk.li))
      (then
        (out.str "<li>")
        (if (global.get $fmt) (then (call $mark (i32.const 2) (i32.const 0))))
        (if (i32.and (global.get $ext) (i32.const 32))
          (then
            (global.set $out (i32.sub (global.get $out) (i32.const 1)))
            (call $outSourcePos (i32.load offset=8 (local.get $r)) (call $itemEnd (local.get $r)))
            (call $outByte (i32.const ">"))))
        (return)))
    (if (i32.and (i32.eq (local.get $t) (enum.get $Blk.ol))
          (i32.ne (i32.load offset=8 (local.get $r)) (i32.const 1)))
      (then
        (if (global.get $fmt)
          (then (out.str "<ol data-markdown=\22ol\22 start=\22"))
          (else (out.str "<ol start=\22")))
        (call $outNum (i32.load offset=8 (local.get $r)))
        (out.str "\22>\n")
        (return)))
    ;; "<ol>" is "<ul>" with `u` lowered by six
    (call $outSmall (i64.sub (i64.const "<ul>\n")
      (i64.extend_i32_u (i32.mul (i32.eq (local.get $t) (enum.get $Blk.ol)) (i32.const 0x600))))
      (i32.const 5))
    (if (global.get $fmt) (then (call $mark (i32.const 2) (i32.const 1)))))

  (func $htmlBlockClose (param $t i32)
    (if (i32.eq (local.get $t) (enum.get $Blk.li))
      (then (out.str "</li>\n") (return)))
    (call $cr)
    (if (i32.eq (local.get $t) (enum.get $Blk.quote))
      (then (out.str "</blockquote>\n") (return)))
    (call $outSmall (i64.sub (i64.const "</ul>\n")
      (i64.extend_i32_u (i32.mul (i32.eq (local.get $t) (enum.get $Blk.ol)) (i32.const 0x60000))))
      (i32.const 6)))

  (func $htmlLeaf (param $t i32) (param $r i32)
    (local $n i32)
    (if (i32.eq (local.get $t) (enum.get $Blk.directive))
      (then
        (call $htmlLeafDirective (local.get $r))
        (return)))
    (block $table
      (block $p
        (block $html
          (block $code
            (block $heading
              (block $hr
                (br_table $hr $heading $code $html $p $table
                  (i32.sub (local.get $t) (enum.get $Blk.hr))))
              (call $cr)
              (if (global.get $fmt)
                (then (out.str "<hr data-markdown=\22hr\22>\n"))
                (else (out.str "<hr />\n")))
              (return))
            ;; "<hN>" and "</hN>" put the level digit into a literal "0"
            (local.set $n (i32.load offset=8 (local.get $r)))
            (call $cr)
            (call $outSmall (i64.extend_i32_u
              (i32.or (i32.const "<h0>") (i32.shl (local.get $n) (i32.const 16)))) (i32.const 4))
            (if (global.get $fmt) (then (call $mark (i32.const 2) (i32.const 0))))
            (call $renderInline (local.get $r))
            (call $outSmall (i64.or (i64.const "</h0>\n")
              (i64.shl (i64.extend_i32_u (local.get $n)) (i64.const 24))) (i32.const 6))
            (return))
          (if (i32.and (global.get $ext) (i32.const 2))
            (then (if (call $mathBlock (local.get $r)) (then (return)))))
          (if (global.get $fmt)
            (then (call $htmlCodeBlockFmt (local.get $r)))
            (else (call $htmlCodeBlock (local.get $r))))
          (return))
        (call $htmlRawBlock (local.get $r))
        (return))
      ;; a tight list item's paragraph has no tags
      (local.set $n (call $tightParagraph))
      (if (i32.eqz (local.get $n))
        (then
          (call $cr)
          (out.str "<p>")
          (if (global.get $fmt) (then (call $mark (i32.const 1) (i32.const 0))))))
      (call $htmlTaskBox)
      (call $renderInline (local.get $r))
      (if (i32.eqz (local.get $n))
        (then (out.str "</p>\n")))
      (return))
    (call $htmlTable (local.get $r)))

  ;; GFM renders a task list item's marker as a disabled checkbox
  (func $htmlTaskBox
    (if (i32.eqz (global.get $pendingTask)) (then (return)))
    (if (global.get $fmt)
      (then
        (out.str "<input data-markdown=\22input\22")
        (if (i32.eq (global.get $pendingTask) (i32.const 2))
          (then (out.str " checked=\22\22")))
        (out.str " disabled=\22\22 type=\22checkbox\22 readonly=\22\22>")
        (global.set $pendingTask (i32.const 0))
        (return)))
    ;; the unchecked tail is a pooled substring of the checked box
    (if (i32.eq (global.get $pendingTask) (i32.const 2))
      (then (out.str "<input checked=\22\22 disabled=\22\22 type=\22checkbox\22>"))
      (else
        (out.str "<input ")
        (out.str "disabled=\22\22 type=\22checkbox\22>")))
    (global.set $pendingTask (i32.const 0)))

  ;; Reserve the worst case once, then resolve content pointers, which growth
  ;; may move. Line endings become spaces.
  (func $htmlCodeSpan (param $beg i32) (param $end i32)
    (local $dst i32)
    (local $q i32)
    (call $ensureOut (i32.add
      (i32.mul (i32.sub (local.get $end) (local.get $beg)) (i32.const 6))
      (i32.const 48)))
    (local.set $dst (global.get $out))
    (i64.store (local.get $dst) (i64.const "<code>"))
    (local.set $dst (i32.add (local.get $dst) (i32.const 6)))
    (if (global.get $fmt) (then (local.set $dst (call $markAt (local.get $dst) (i32.const 4)))))
    (local.set $beg (call $contentAt (local.get $beg)))
    (local.set $end (call $contentAt (local.get $end)))
    (block $done
      (loop $line
        (local.set $q (local.get $end))
        (if (i32.eqz (global.get $singleLineContent))
          (then (local.set $q (call $findByte (local.get $beg) (local.get $end) (i32.const 10)))))
        (local.set $dst (call $outTextAt (local.get $beg) (local.get $q) (local.get $dst)))
        (br_if $done (i32.ge_u (local.get $q) (local.get $end)))
        (i32.store8 (local.get $dst) (i32.const 32))
        (local.set $dst (i32.add (local.get $dst) (i32.const 1)))
        (local.set $beg (i32.add (local.get $q) (i32.const 1)))
        (br $line)))
    (i64.store (local.get $dst) (i64.const "</code>"))
    (global.set $out (i32.add (local.get $dst) (i32.const 7))))

  (func $htmlCodeBlock (param $r i32)
    (local $word i32)
    (call $cr)
    (out.str "<pre")
    ;; Only sessions mark an open fence.
    (if (i32.and (i32.ne (i32.and (i32.load8_u (i32.const 1)) (i32.const 8)) (i32.const 0))
          (i32.eq (local.get $r) (global.get $incompleteCodeRec)))
      (then (out.str " data-markdown-incomplete")))
    (call $outCodeSourcePos (local.get $r))
    (out.str "><code class=\22language-")
    (local.set $word (global.get $out))
    (call $htmlInfoWord (local.get $r))
    (if (i32.eq (global.get $out) (local.get $word))
      (then
        (global.set $out (i32.sub (local.get $word) (i32.const 22)))
        (out.str "<code>"))
      (else
        (call $outByte (i32.const 34))
        (call $htmlCodeMeta (local.get $r))
        (call $outByte (i32.const ">"))))
    (call $htmlCodeLines (local.get $r))
    (out.str "</code></pre>\n"))

  ;; codeMeta: ` data-meta="..."` with the info string after its first word,
  ;; trimmed, its escapes and entities resolved as for the language.
  (func $htmlCodeMeta (param $r i32)
    (local $p i32)
    (local $e i32)
    (if (i32.eqz (i32.and (global.get $ext) (i32.const 16))) (then (return)))
    (local.set $p (i32.load offset=8 (local.get $r)))
    (local.set $e (i32.load offset=12 (local.get $r)))
    (block $word
      (loop $l
        (br_if $word (i32.ge_u (local.get $p) (local.get $e)))
        (br_if $word (call $isWhiteByte (i32.load8_u (local.get $p))))
        (local.set $p (i32.add (local.get $p) (i32.const 1)))
        (br $l)))
    (local.set $p (call $skipWs (local.get $p) (local.get $e)))
    (block $trimmed
      (loop $l
        (br_if $trimmed (i32.le_u (local.get $e) (local.get $p)))
        (br_if $trimmed (i32.eqz (call $isWhiteByte
          (i32.load8_u (i32.sub (local.get $e) (i32.const 1))))))
        (local.set $e (i32.sub (local.get $e) (i32.const 1)))
        (br $l)))
    (if (i32.ge_u (local.get $p) (local.get $e)) (then (return)))
    (call $ensureOut (i32.add
      (i32.mul (i32.sub (local.get $e) (local.get $p)) (i32.const 12)) (i32.const 64)))
    (out.str " data-meta=\22")
    (call $outCleanText (local.get $p) (local.get $e) (i32.const 3))
    (call $outByte (i32.const 34)))

  ;; write $n spaces, at most eight (a line's virtual tab padding)
  (func $outSpaces (param $n i32)
    (call $ensureOut (i32.const 8))
    (i64.store (global.get $out) (i64.const 0x2020202020202020))
    (global.set $out (i32.add (global.get $out) (local.get $n))))

  (func $htmlRawBlock (param $r i32)
    (local $n i32)
    (local $i i32)
    (local $line i32)
    ;; skipped raw HTML leaves no line breaks behind
    (if (i32.and (i32.load8_u (i32.const 1)) (i32.const 2)) (then (return)))
    (call $cr)
    (local.set $n (i32.load offset=$R.nLines (local.get $r)))
    (block $done
      (loop $l
        (br_if $done (i32.ge_u (local.get $i) (local.get $n)))
        (local.set $line (call $lineAt (local.get $r) (local.get $i)))
        (call $outSpaces (call $linePad (local.get $line)))
        ;; escapeHtml: raw HTML is text. Lines are input-backed, so $outText may grow output.
        (if (i32.and (global.get $ext) (i32.const 128))
          (then (call $outText (call $lineBeg (local.get $line)) (call $lineEndOf (local.get $line))))
          (else
            (call $htmlFiltered2 (call $lineBeg (local.get $line)) (call $lineEndOf (local.get $line))
              (i32.const 1))))
        (call $outByte (i32.const 10))
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $l))))

  ;; raw HTML passes through, except that GFM escapes a handful of tag names
  (func $htmlFiltered2 (param $p i32) (param $e i32) (param $eol i32)
    (local $q i32)
    (local $n i32)
    (local $tag i32)
    (local $tagEnd i32)
    ;; structured React output drops raw HTML
    (if (i32.and (i32.load8_u (i32.const 1)) (i32.const 2)) (then (return)))
    ;; escapeHtml: raw HTML is text. The caller reserved six bytes per input byte.
    (if (i32.and (global.get $ext) (i32.const 128))
      (then (call $outTextReserved (local.get $p) (local.get $e)) (return)))
    (block $done
      (loop $l
        (br_if $done (i32.ge_u (local.get $p) (local.get $e)))
        (local.set $q (call $findByte (local.get $p) (local.get $e) (i32.const "<")))
        ;; NUL is U+FFFD, as in text
        (local.set $tag (call $findByte (local.get $p) (local.get $q) (i32.const 0)))
        (if (i32.lt_u (local.get $tag) (local.get $q))
          (then
            (call $outCopy (local.get $p) (local.get $tag))
            (out.str "\ef\bf\bd")
            (local.set $p (i32.add (local.get $tag) (i32.const 1)))
            (br $l)))
        (call $outCopy (local.get $p) (local.get $q))
        (br_if $done (i32.ge_u (local.get $q) (local.get $e)))
        (local.set $tag (i32.add (local.get $q) (i32.const 1)))
        (if (i32.and (i32.lt_u (local.get $tag) (local.get $e))
              (i32.eq (i32.load8_u (local.get $tag)) (i32.const "/")))
          (then (local.set $tag (i32.add (local.get $tag) (i32.const 1)))))
        (local.set $n (call $scanTagName (local.get $tag) (local.get $e)))
        (if (i32.and (i32.ne (local.get $n) (i32.const 0))
              (call $wordLookup
                (i32.const $mem.filterTags) (local.get $tag) (local.get $n) (i32.const 9)))
          (then
            (local.set $tagEnd (i32.add (local.get $tag) (local.get $n)))
            ;; the name must end the tag: space, >, or />; the line end counts
            ;; for whole raw lines. Lookahead past $e stays inside input slack.
            (if (if (result i32) (i32.ge_u (local.get $tagEnd) (local.get $e))
                  (then (local.get $eol))
                  (else
                    (local.set $n (i32.load8_u (local.get $tagEnd)))
                    (i32.or
                      (i32.or (call $isWhiteByte (local.get $n)) (i32.eq (local.get $n) (i32.const ">")))
                      (i32.and
                        (i32.and (i32.eq (local.get $n) (i32.const "/"))
                          (i32.lt_u (i32.add (local.get $tagEnd) (i32.const 1)) (local.get $e)))
                        (i32.eq (i32.load8_u offset=1 (local.get $tagEnd)) (i32.const ">"))))))
              (then
                (out.str "&lt;")
                (local.set $p (i32.add (local.get $q) (i32.const 1)))
                (br $l)))))
        (call $outByte (i32.const "<"))
        (local.set $p (i32.add (local.get $q) (i32.const 1)))
        (br $l))))

  (func $htmlTable (param $r i32)
    (local $cols i32)
    (local $rows i32)
    (local $i i32)
    (call $cr)
    (local.set $cols (i32.load offset=8 (local.get $r)))
    (local.set $rows (i32.load offset=$R.nLines (local.get $r)))
    (if (global.get $fmt)
      (then (out.str "<table data-markdown=\22table\22>\n<thead data-markdown=\22thead\22>\n"))
      (else (out.str "<table>\n<thead>\n")))
    (call $htmlTableRow (local.get $r) (i32.const 0) (local.get $cols) (i32.const 1))
    (out.str "</thead>\n")
    (if (i32.gt_u (local.get $rows) (i32.const 1))
      (then
        (out.str "<tbody>\n")
        (if (global.get $fmt) (then (call $mark (i32.const 5) (i32.const 1))))
        (local.set $i (i32.const 1))
        (block $done
          (loop $l
            (br_if $done (i32.ge_u (local.get $i) (local.get $rows)))
            (call $htmlTableRow (local.get $r) (local.get $i) (local.get $cols) (i32.const 0))
            (local.set $i (i32.add (local.get $i) (i32.const 1)))
            (br $l)))
        (out.str "</tbody>\n")))
    (out.str "</table>\n"))

  (func $htmlTableRow (param $r i32) (param $row i32) (param $cols i32) (param $head i32)
    (local $line i32)
    (local $i i32)
    (local $align i32)
    (local $p i32)
    (local $end i32)
    (local $has i32)
    (local.set $line (call $lineAt (local.get $r) (local.get $row)))
    (local.set $p (call $lineBeg (local.get $line)))
    (local.set $end (call $lineEndOf (local.get $line)))
    (if (i32.lt_u (local.get $p) (local.get $end))
      (then
        (if (i32.eq (i32.load8_u (local.get $p)) (i32.const "|"))
          (then
            (local.set $p
              (call $skipSpace (i32.add (local.get $p) (i32.const 1)) (local.get $end)))))))
    (out.str "<tr>\n")
    (if (global.get $fmt) (then (call $mark (i32.const 2) (i32.const 1))))
    (block $done
      (loop $l
        (br_if $done (i32.ge_u (local.get $i) (local.get $cols)))
        (local.set $align (i32.load8_u
          (i32.add (i32.add (local.get $r) (i32.const $R.header)) (local.get $i))))
        (call $htmlCellOpen (local.get $head) (local.get $align))
        (local.set $has (call $cellRange (local.get $p) (local.get $end)))
        (local.set $p (global.get $cellNext))
        (if (local.get $has)
          (then (call $renderCell (global.get $cellBeg) (global.get $cellEnd)
            (global.get $cellUnescapePipe))))
        (call $outSmall (select (i64.const "</th>\n") (i64.const "</td>\n") (local.get $head))
          (i32.const 6))
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $l)))
    (out.str "</tr>\n"))

  ;; The whole cell opener under one reservation. Formatted cells align with
  ;; a style.
  (func $htmlCellOpen (param $head i32) (param $align i32)
    (local $dst i32)
    (call $ensureOut (i32.const 56))
    (local.set $dst (i32.add (global.get $out) (i32.const 4)))
    (i32.store (global.get $out) (select
      (i32.const "<th>") (i32.const "<td>") (local.get $head)))
    (if (global.get $fmt) (then (local.set $dst (call $markAt (local.get $dst) (i32.const 2)))))
    (if (local.get $align)
      (then
        ;; the attribute starts over the closing angle bracket
        (if (global.get $fmt)
          (then
            (i64.store (i32.sub (local.get $dst) (i32.const 1)) (i64.const " style=\22"))
            (i64.store offset=7 (local.get $dst) (i64.const "text-ali"))
            (i32.store offset=15 (local.get $dst) (i32.const "gn:"))
            (local.set $dst (i32.add (local.get $dst) (i32.const 18))))
          (else
            (i64.store (i32.sub (local.get $dst) (i32.const 1)) (i64.const " align=\22"))
            (local.set $dst (i32.add (local.get $dst) (i32.const 7)))))
        (i64.store (local.get $dst) (select
          (i64.const "left\22>")
          (select (i64.const "center\22>") (i64.const "right\22>")
            (i32.eq (local.get $align) (i32.const $A.center)))
          (i32.eq (local.get $align) (i32.const $A.left))))
        (local.set $dst (i32.add (local.get $dst) (select (i32.const 6)
          (select (i32.const 8) (i32.const 7)
            (i32.eq (local.get $align) (i32.const $A.center)))
          (i32.eq (local.get $align) (i32.const $A.left)))))))
    (global.set $out (local.get $dst)))

  ;; write footnote $n's reference id: "n", or "n-k" for its $k-th reference
  (func $outRefId (param $n i32) (param $k i32)
    (call $outNum (local.get $n))
    (if (i32.gt_u (local.get $k) (i32.const 1))
      (then
        (call $outByte (i32.const "-"))
        (call $outNum (local.get $k)))))

  (func $htmlFootnoteRef (param $n i32) (param $k i32)
    (if (global.get $fmt)
      (then (out.str "<sup data-markdown=\22sup\22 class=\22footnote-ref\22><a data-markdown=\22a\22 href=\22#"))
      (else (out.str "<sup class=\22footnote-ref\22><a href=\22#")))
    (call $outIdPrefix (i32.const 1))
    (out.str "fn-")
    (call $outNum (local.get $n))
    (out.str "\22 id=\22")
    (call $outIdPrefix (i32.const 0))
    (out.str "fnref-")
    (call $outRefId (local.get $n) (local.get $k))
    (out.str "\22 data-footnote-ref>")
    (call $outNum (local.get $n))
    (out.str "</a></sup>"))

  (func $htmlFootnotesOpen
    (call $cr)
    (if (global.get $fmt)
      (then (out.str "<section data-markdown=\22section\22 class=\22footnotes\22 data-footnotes>\n<ol data-markdown=\22ol\22>\n"))
      (else (out.str "<section class=\22footnotes\22 data-footnotes>\n<ol>\n"))))

  (func $htmlFootnotesClose
    (call $cr)
    (out.str "</ol>\n</section>\n"))

  (func $htmlFootnoteOpen (param $n i32)
    (call $cr)
    (if (global.get $fmt)
      (then (out.str "<li data-markdown=\22li\22 id=\22"))
      (else (out.str "<li id=\22")))
    (call $outIdPrefix (i32.const 0))
    (out.str "fn-")
    (call $outNum (local.get $n))
    (out.str "\22>\n"))

  ;; the back references belong at the end of the last paragraph, so rewind
  ;; over its closing tag and write them inside it
  (func $htmlFootnoteClose (param $n i32) (param $def i32)
    (local $k i32)
    (local $inside i32)
    (local.set $k (i32.const 1))
    (if (i32.ge_u (global.get $out) (i32.add (global.get $outBase) (i32.const 5)))
      (then
        (if (i64.eq (i64.and (i64.load (i32.sub (global.get $out) (i32.const 5)))
              (i64.const 0xffffffffff)) (i64.const "</p>\n"))
          (then
            (local.set $inside (i32.const 1))
            (global.set $out (i32.sub (global.get $out) (i32.const 5)))))))
    (block $done
      (loop $l
        (br_if $done (i32.gt_u (local.get $k) (i32.load offset=12 (local.get $def))))
        (if (global.get $fmt)
          (then (out.str " <a data-markdown=\22a\22 href=\22#"))
          (else (out.str " <a href=\22#")))
        (call $outIdPrefix (i32.const 1))
        (out.str "fnref-")
        (call $outRefId (local.get $n) (local.get $k))
        (out.str "\22 class=\22footnote-backref\22 data-footnote-backref data-footnote-backref-idx=\22")
        (call $outRefId (local.get $n) (local.get $k))
        (out.str "\22 aria-label=\22Back to reference ")
        (call $outRefId (local.get $n) (local.get $k))
        (out.str "\22>\e2\86\a9")
        ;; later back-links show their number, as cmark-gfm does
        (if (i32.gt_u (local.get $k) (i32.const 1))
          (then
            (if (global.get $fmt)
              (then (out.str "<sup data-markdown=\22sup\22 class=\22footnote-ref\22>"))
              (else (out.str "<sup class=\22footnote-ref\22>")))
            (call $outNum (local.get $k))
            (out.str "</sup>")))
        (out.str "</a>")
        (local.set $k (i32.add (local.get $k) (i32.const 1)))
        (br $l)))
    (if (local.get $inside) (then (out.str "</p>\n")))
    (call $cr)
    (out.str "</li>\n"))

  ;; Write the link URL percent-encoded; $flags is as for $outHref. Its
  ;; reservation leaves 64 bytes for the attribute boundaries that follow.
  (func $htmlUrl (param $flags i32)
    (local $p i32)
    (local $c i32)
    (call $ensureOut (i32.add (i32.mul
      (i32.sub (global.get $linkUrlEnd) (global.get $linkUrlBeg)) (i32.const 9)) (i32.const 64)))
    (local.set $p (i32.add (call $linkBase) (global.get $linkUrlBeg)))
    ;; windowsPaths: every backslash of a drive path destination is literal
    (if (i32.and (global.get $ext) (i32.const 8))
      (then
        (local.set $c (i32.load8_u offset=2 (local.get $p)))
        (if (i32.and
              (i32.and
                (i32.ge_u (i32.sub (global.get $linkUrlEnd) (global.get $linkUrlBeg)) (i32.const 3))
                (call $isAlpha (i32.load8_u (local.get $p))))
              (i32.and (i32.eq (i32.load8_u offset=1 (local.get $p)) (i32.const ":"))
                (i32.or (i32.eq (local.get $c) (i32.const "\5c")) (i32.eq (local.get $c) (i32.const "/")))))
          (then (local.set $flags (i32.and (local.get $flags) (i32.const -3)))))))
    (call $outHref (local.get $p)
      (i32.add (call $linkBase) (global.get $linkUrlEnd)) (local.get $flags)))

  ;; Write a link range as cleaned, escaped text; $flags is as for $outCleanText.
  (func $htmlLinkText (param $beg i32) (param $end i32) (param $flags i32)
    (call $ensureOut (i32.add (i32.mul
      (i32.sub (local.get $end) (local.get $beg)) (i32.const 12)) (i32.const 64)))
    (call $outCleanText (i32.add (call $linkBase) (local.get $beg))
      (i32.add (call $linkBase) (local.get $end)) (local.get $flags)))

  ;; Write ` title="..."` when the link has a title, without its closing quote.
  (func $htmlTitle
    (if (i32.ne (global.get $linkTitleEnd) (global.get $linkTitleBeg))
      (then
        (out.str "\22 title=\22")
        (call $htmlLinkText (global.get $linkTitleBeg) (global.get $linkTitleEnd) (i32.const 3)))))

  (func $htmlLinkOpen (param $image i32)
    (local $url i32)
    (if (local.get $image)
      (then
        (global.set $imgDrop (global.get $out))
        (if (global.get $fmt)
          (then (out.str "<img data-markdown=\22img\22 src=\22"))
          (else (out.str "<img src=\22")))
        (local.set $url (global.get $out))
        (call $htmlUrl (i32.const 3))
        ;; a formatted image whose URL fails the rules is dropped when it closes
        (if (i32.or (i32.eqz (global.get $fmt))
              (call $urlAllowed (local.get $url) (global.get $out)))
          (then (global.set $imgDrop (i32.const 0))))
        (out.str "\22 alt=\22")
        (return)))
    ;; No destination yet: an inert anchor around the label. Completion's
    ;; placeholder (option bit 4) is known by its input position, counted back
    ;; from the end of the content, so a source that writes the same URL keeps it.
    (if (i32.or (global.get $linkPending)
          (i32.and
            (i32.and (i32.shr_u (i32.load8_u (i32.const 1)) (i32.const 4)) (global.get $linkInContent))
            (i32.eq (global.get $completePlaceholder)
              (i32.sub (i32.add (global.get $contentInputEnd) (global.get $linkUrlBeg))
                (global.get $contentLen)))))
      (then
        (if (global.get $fmt)
          (then (out.str "<a data-markdown=\22incomplete-link\22>"))
          (else (out.str "<a data-markdown-incomplete>")))
        (return)))
    (if (global.get $fmt)
      (then
        (out.str "<a data-markdown=\22a\22")
        (call $htmlHref (i32.const 0) (i32.const 3))
        (if (i32.ne (global.get $linkTitleEnd) (global.get $linkTitleBeg))
          (then
            (out.str " title=\22")
            (call $htmlLinkText (global.get $linkTitleBeg) (global.get $linkTitleEnd) (i32.const 3))
            (call $outByte (i32.const 34))))
        (call $outLinkSourcePos (i32.const 0))
        (call $outByte (i32.const ">"))
        (return)))
    (out.str "<a href=\22")
    (call $htmlUrl (i32.const 3))
    (call $htmlTitle)
    (call $outByte (i32.const 34))
    (call $outLinkSourcePos (i32.const 0))
    (call $outByte (i32.const ">")))

  (func $htmlLinkClose (param $image i32)
    (if (local.get $image)
      (then
        (call $htmlTitle)
        (call $outByte (i32.const 34))
        (call $outLinkSourcePos (i32.const 1))
        (if (global.get $fmt)
          (then
            (out.str " loading=\22lazy\22>")
            (if (global.get $imgDrop) (then (global.set $out (global.get $imgDrop)))))
          (else (out.str " />")))
        (return)))
    (out.str "</a>"))

  ;; $kind 1 adds http:// and 2 adds mailto:. $flags selects the URL and text
  ;; cleanup, as for $outHref: autolinks decode entities, extended ones do not.
  (func $htmlAutolink (param $kind i32) (param $flags i32)
    (if (global.get $fmt)
      (then
        (out.str "<a data-markdown=\22a\22")
        (call $htmlHref (local.get $kind) (local.get $flags))
        (call $outLinkSourcePos (i32.const 0))
        (call $outByte (i32.const ">")))
      (else
        (out.str "<a href=\22")
        (if (i32.eq (local.get $kind) (i32.const 1)) (then (out.str "http://")))
        (if (i32.eq (local.get $kind) (i32.const 2)) (then (out.str "mailto:")))
        (call $htmlUrl (local.get $flags))
        (call $outByte (i32.const 34))
        (call $outLinkSourcePos (i32.const 0))
        (call $outByte (i32.const ">"))))
    (call $htmlLinkText (global.get $linkUrlBeg) (global.get $linkUrlEnd) (local.get $flags))
    (out.str "</a>"))

  ;; sourcePositions (extension bit 5)

  ;; The input offset of content offset $off: rebuilt content maps back
  ;; through its record's lines, or for a cell past its escaped pipes.
  (func $srcOffset (param $off i32) (result i32)
    (local $p i32)
    (block $mapped
      (if (i32.lt_u (global.get $contentBase) (global.get $eof))
        (then
          (local.set $p (i32.add (global.get $contentBase) (local.get $off)))
          (br $mapped)))
      (if (global.get $contentRec)
        (then
          (local.set $p (call $completeInputAt (global.get $contentRec) (local.get $off)))
          (br $mapped)))
      (local.set $p (global.get $cellSrc))
      (block $done
        (loop $l
          (br_if $done (i32.eqz (local.get $off)))
          (local.set $p (i32.add (local.get $p) (i32.add (i32.const 1)
            (i32.eq (i32.load16_u (local.get $p)) (i32.const 0x7c5c)))))
          (local.set $off (i32.sub (local.get $off) (i32.const 1)))
          (br $l))))
    (local.get $p))

  ;; the data-sourcepos attribute of the input range [$beg, $end)
  (func $outSourcePos (param $beg i32) (param $end i32)
    (local $base i32)
    (local.set $base (i32.sub (i32.load (i32.const 44)) (i32.const $mem.input)))
    (out.str " data-sourcepos=\22")
    (call $outNum (i32.add (local.get $base) (local.get $beg)))
    (call $outByte (i32.const "-"))
    (call $outNum (i32.add (local.get $base) (local.get $end)))
    (call $outByte (i32.const 34)))

  ;; The content range of the link, image, or directive that renders next, as
  ;; input ranges. An image keeps its own until it closes.
  (global $spBeg (mut i32) (i32.const 0))
  (global $spEnd (mut i32) (i32.const 0))
  (global $imgSpBeg (mut i32) (i32.const 0))
  (global $imgSpEnd (mut i32) (i32.const 0))

  (func $noteSourcePos (param $b i32) (param $e i32) (param $image i32)
    (local.set $b (call $srcOffset (local.get $b)))
    (local.set $e (call $srcOffset (local.get $e)))
    (if (local.get $image)
      (then
        (global.set $imgSpBeg (local.get $b))
        (global.set $imgSpEnd (local.get $e)))
      (else
        (global.set $spBeg (local.get $b))
        (global.set $spEnd (local.get $e)))))

  (func $outLinkSourcePos (param $image i32)
    (if (i32.eqz (i32.and (global.get $ext) (i32.const 32))) (then (return)))
    (if (local.get $image)
      (then (call $outSourcePos (global.get $imgSpBeg) (global.get $imgSpEnd)))
      (else (call $outSourcePos (global.get $spBeg) (global.get $spEnd)))))

  ;; The end of a list marker at $p: digits and a delimiter, or a bullet.
  (func $markerEnd (param $p i32) (result i32)
    (if (i32.eqz (call $isDigit (i32.load8_u (local.get $p))))
      (then (return (i32.add (local.get $p) (i32.const 1)))))
    (loop $digits
      (local.set $p (i32.add (local.get $p) (i32.const 1)))
      (br_if $digits (call $isDigit (i32.load8_u (local.get $p)))))
    (i32.add (local.get $p) (i32.const 1)))

  ;; The end of item $r as mdast measures it: its last content byte. Leaves
  ;; end with their trimmed last line; a fenced code block with its closing
  ;; fence.
  (func $itemEnd (param $r i32) (result i32)
    (local $e i32)
    (local $q i32)
    (local $t i32)
    (local $f i32)
    (local $n i32)
    (local $depth i32)
    (local.set $e (call $markerEnd (i32.load offset=8 (local.get $r))))
    (local.set $r (i32.add (local.get $r) (i32.load offset=4 (local.get $r))))
    (block $done
      (loop $l
        (br_if $done (i32.ge_u (local.get $r) (global.get $recEnd)))
        (local.set $t (i32.load8_u (local.get $r)))
        (local.set $f (i32.load8_u offset=1 (local.get $r)))
        (local.set $q (i32.const 0))
        (if (i32.and (local.get $f) (i32.const $F.closer))
          (then
            (br_if $done (i32.eqz (local.get $depth)))
            (local.set $depth (i32.sub (local.get $depth) (i32.const 1))))
          (else
            (if (i32.and (local.get $f) (i32.const $F.opener))
              (then
                (local.set $depth (i32.add (local.get $depth) (i32.const 1)))
                (if (i32.eq (local.get $t) (enum.get $Blk.li))
                  (then (local.set $q (call $markerEnd (i32.load offset=8 (local.get $r)))))))
              (else
                (if (i32.ne (local.get $t) (enum.get $Blk.none))
                  (then
                    (local.set $n (i32.load offset=$R.nLines (local.get $r)))
                    (if (local.get $n)
                      (then (local.set $q (call $lineEndOf
                        (call $lineAt (local.get $r) (i32.sub (local.get $n) (i32.const 1))))))
                      (else
                        (if (i32.eq (local.get $t) (enum.get $Blk.code))
                          (then (local.set $q (i32.load offset=12 (local.get $r)))))))
                    (if (local.get $q)
                      (then
                        (if (i32.and (i32.eq (local.get $t) (enum.get $Blk.code))
                              (i32.ne (i32.and (local.get $f) (i32.const $F.fenced)) (i32.const 0)))
                          (then (local.set $q (call $fenceEnd (local.get $r) (local.get $q))))
                          (else (local.set $q (call $trimmedLineEnd (local.get $q)))))))))))))
        (if (i32.gt_u (local.get $q) (local.get $e)) (then (local.set $e (local.get $q))))
        (local.set $r (i32.add (local.get $r) (i32.load offset=4 (local.get $r))))
        (br $l)))
    (local.get $e))

  ;; The end of the line at $p without trailing spaces and tabs, not before $p.
  (func $trimmedLineEnd (param $p i32) (result i32)
    (call $trimSpaceBack (call $findLineEnd (local.get $p)) (local.get $p)))

  ;; The end of fenced code block $r whose content ends at $q: past its
  ;; closing fence when the next line holds one.
  (func $fenceEnd (param $r i32) (param $q i32) (result i32)
    (local $c i32)
    (local $p i32)
    (local $e i32)
    (local $n i32)
    ;; the fence character ends the run before the info string
    (local.set $p (i32.load offset=8 (local.get $r)))
    (loop $back
      (local.set $c (i32.load8_u (local.tee $p (i32.sub (local.get $p) (i32.const 1)))))
      (br_if $back (call $isSpaceByte (local.get $c))))
    (local.set $q (call $trimmedLineEnd (local.get $q)))
    (local.set $p (call $lineAfter (call $findLineEnd (local.get $q))))
    (if (i32.ge_u (local.get $p) (global.get $eof)) (then (return (local.get $q))))
    (local.set $e (call $findLineEnd (local.get $p)))
    ;; container prefixes: indents and quote markers
    (block $prefix
      (loop $l
        (br_if $prefix (i32.ge_u (local.get $p) (local.get $e)))
        (br_if $prefix (i32.eqz (i32.or (call $isSpaceByte (i32.load8_u (local.get $p)))
          (i32.eq (i32.load8_u (local.get $p)) (i32.const ">")))))
        (local.set $p (i32.add (local.get $p) (i32.const 1)))
        (br $l)))
    (local.set $e (i32.sub (call $runEnd (local.get $p) (local.get $e) (local.get $c)) (local.get $p)))
    (if (i32.ge_u (local.get $e)
          (select (i32.const 2) (i32.const 3) (i32.eq (local.get $c) (i32.const "$"))))
      (then (return (call $findLineEnd (local.get $p)))))
    (local.get $q))

  ;; The start of the fence run of fenced code block $r.
  (func $fenceStart (param $r i32) (result i32)
    (local $p i32)
    (local $c i32)
    (local.set $p (i32.load offset=8 (local.get $r)))
    (loop $back
      (local.set $c (i32.load8_u (local.tee $p (i32.sub (local.get $p) (i32.const 1)))))
      (br_if $back (call $isSpaceByte (local.get $c))))
    ;; a `\[` math block
    (if (i32.eq (local.get $c) (i32.const "[")) (then (return (i32.sub (local.get $p) (i32.const 1)))))
    (loop $run
      (br_if $run (i32.eq (i32.load8_u (local.tee $p (i32.sub (local.get $p) (i32.const 1))))
        (local.get $c))))
    (i32.add (local.get $p) (i32.const 1)))

  ;; The data-sourcepos of code block $r, as mdast measures it: a fenced
  ;; block from its opening fence through its closing fence line, an indented
  ;; one over its indented lines.
  (func $outCodeSourcePos (param $r i32)
    (local $n i32)
    (local $p i32)
    (local $q i32)
    (local $k i32)
    (if (i32.eqz (i32.and (global.get $ext) (i32.const 32))) (then (return)))
    (local.set $n (i32.load offset=$R.nLines (local.get $r)))
    (if (local.get $n)
      (then (local.set $q (call $lineEndOf
        (call $lineAt (local.get $r) (i32.sub (local.get $n) (i32.const 1)))))))
    (if (i32.and (i32.load8_u offset=1 (local.get $r)) (i32.const $F.fenced))
      (then
        (if (i32.eqz (local.get $n)) (then (local.set $q (i32.load offset=12 (local.get $r)))))
        (call $outSourcePos (call $fenceStart (local.get $r))
          (call $fenceEnd (local.get $r) (local.get $q)))
        (return)))
    ;; the indent before the first line: four columns, or a tab
    (local.set $p (call $lineBeg (call $lineAt (local.get $r) (i32.const 0))))
    (block $indent
      (loop $back
        (br_if $indent (i32.ge_u (local.get $k) (i32.const 4)))
        (br_if $indent (i32.eqz (call $isSpaceByte (i32.load8_u (i32.sub (local.get $p) (i32.const 1))))))
        (local.set $p (i32.sub (local.get $p) (i32.const 1)))
        (local.set $k (select (i32.const 4) (i32.add (local.get $k) (i32.const 1))
          (i32.eq (i32.load8_u (local.get $p)) (i32.const 9))))
        (br $back)))
    (call $outSourcePos (local.get $p) (local.get $q)))

  ;; The input range of the math that renders next, while $mathSp is set.
  (global $mathSp (mut i32) (i32.const 0))
  (global $mathSpBeg (mut i32) (i32.const 0))
  (global $mathSpEnd (mut i32) (i32.const 0))

  (func $noteMathSourcePos (param $b i32) (param $e i32)
    (global.set $mathSpBeg (local.get $b))
    (global.set $mathSpEnd (local.get $e))
    (global.set $mathSp (i32.const 1)))

  ;; Math block $r from its opening fence through its closing one: `$$` or
  ;; `\]` ends the last line or the next one. A `math` code fence measures
  ;; as code.
  (func $mathBlockSourcePos (param $r i32)
    (local $n i32)
    (local $q i32)
    (local $e i32)
    (local $t i32)
    (local.set $n (i32.load offset=$R.nLines (local.get $r)))
    (local.set $q (select
      (call $lineEndOf (call $lineAt (local.get $r) (i32.sub (local.get $n) (i32.const 1))))
      (i32.load offset=12 (local.get $r))
      (local.get $n)))
    (if (i32.eqz (i32.and (i32.load8_u offset=1 (local.get $r)) (i32.const $F.math)))
      (then
        (call $noteMathSourcePos (call $fenceStart (local.get $r))
          (call $fenceEnd (local.get $r) (local.get $q)))
        (return)))
    (local.set $e (call $findLineEnd (local.get $q)))
    (local.set $t (call $trimSpaceBack (local.get $e) (local.get $q)))
    ;; the range keeps the spaces after the closing fence
    (if (i32.lt_u (local.get $t) (i32.add (local.get $q) (i32.const 2)))
      (then (local.set $e (call $findLineEnd (call $lineAfter (local.get $e))))))
    (call $noteMathSourcePos (call $fenceStart (local.get $r)) (local.get $e)))

  ;; directives (extension bit 6)

  ;; The end of a directive name at $p: a letter, then letters, digits, `-`
  ;; and `_`. Returns $p when no name starts there.
  (func $dirNameEnd (param $p i32) (param $e i32) (result i32)
    (local $q i32)
    (local $c i32)
    (if (i32.ge_u (local.get $p) (local.get $e)) (then (return (local.get $p))))
    (if (i32.eqz (call $isAlpha (i32.load8_u (local.get $p)))) (then (return (local.get $p))))
    (local.set $q (i32.add (local.get $p) (i32.const 1)))
    (block $done
      (loop $l
        (br_if $done (i32.ge_u (local.get $q) (local.get $e)))
        (local.set $c (i32.load8_u (local.get $q)))
        (br_if $done (i32.eqz (i32.or (call $isAlnum (local.get $c))
          (i32.or (i32.eq (local.get $c) (i32.const "-")) (i32.eq (local.get $c) (i32.const "_"))))))
        (local.set $q (i32.add (local.get $q) (i32.const 1)))
        (br $l)))
    (local.get $q))

  ;; Whether [$p, $e) is one of the names the host wrote below $mem.idPrefixEnd.
  (func $directiveListed (param $p i32) (param $e i32) (result i32)
    (local $at i32)
    (local $n i32)
    (local $i i32)
    (local.set $n (i32.sub (local.get $e) (local.get $p)))
    (if (i32.eqz (local.get $n)) (then (return (i32.const 0))))
    (local.set $at (i32.sub (i32.const $mem.idPrefixEnd) (i32.load16_u (i32.const 32))))
    (block $none
      (loop $names
        (br_if $none (i32.ge_u (local.get $at) (i32.const $mem.idPrefixEnd)))
        (if (i32.eq (i32.load8_u (local.get $at)) (local.get $n))
          (then
            (local.set $i (i32.const 0))
            (block $differ
              (loop $bytes
                (if (i32.ge_u (local.get $i) (local.get $n)) (then (return (i32.const 1))))
                (br_if $differ (i32.ne (i32.load8_u offset=1 (i32.add (local.get $at) (local.get $i)))
                  (i32.load8_u (i32.add (local.get $p) (local.get $i)))))
                (local.set $i (i32.add (local.get $i) (i32.const 1)))
                (br $bytes)))))
        (local.set $at (i32.add (local.get $at) (i32.add (i32.load8_u (local.get $at)) (i32.const 1))))
        (br $names)))
    (i32.const 0))

  ;; The `]` that closes the label opened at $p, with balanced brackets and
  ;; backslash escapes, or 0.
  (func $labelClose (param $p i32) (param $e i32) (result i32)
    (local $depth i32)
    (local $c i32)
    (block $none
      (loop $l
        (local.set $p (i32.add (local.get $p) (i32.const 1)))
        (br_if $none (i32.ge_u (local.get $p) (local.get $e)))
        (local.set $c (i32.load8_u (local.get $p)))
        (if (i32.eq (local.get $c) (i32.const "\5c"))
          (then
            (local.set $p (i32.add (local.get $p) (i32.const 1)))
            (br $l)))
        (if (i32.eq (local.get $c) (i32.const "["))
          (then (local.set $depth (i32.add (local.get $depth) (i32.const 1)))))
        (if (i32.eq (local.get $c) (i32.const "]"))
          (then
            (if (i32.eqz (local.get $depth)) (then (return (local.get $p))))
            (local.set $depth (i32.sub (local.get $depth) (i32.const 1)))))
        (br $l)))
    (i32.const 0))

  ;; Write byte $c of a JSON string inside an HTML attribute, into reserved
  ;; output.
  (func $jsonByte (param $c i32)
    (local $o i32)
    (local.set $o (global.get $out))
    (block $done
      (if (i32.eq (local.get $c) (i32.const 34))
        (then
          (i32.store8 (local.get $o) (i32.const "\5c"))
          (i64.store offset=1 (local.get $o) (i64.const "&quot;"))
          (local.set $o (i32.add (local.get $o) (i32.const 7)))
          (br $done)))
      (if (i32.eq (local.get $c) (i32.const "\5c"))
        (then
          (i32.store16 (local.get $o) (i32.const "\5c\5c"))
          (local.set $o (i32.add (local.get $o) (i32.const 2)))
          (br $done)))
      (if (i32.eq (local.get $c) (i32.const "&"))
        (then
          (i64.store (local.get $o) (i64.const "&amp;"))
          (local.set $o (i32.add (local.get $o) (i32.const 5)))
          (br $done)))
      (if (i32.or (i32.eq (local.get $c) (i32.const "<")) (i32.eq (local.get $c) (i32.const ">")))
        (then
          (i32.store (local.get $o) (select (i32.const "&lt;") (i32.const "&gt;")
            (i32.eq (local.get $c) (i32.const "<"))))
          (local.set $o (i32.add (local.get $o) (i32.const 4)))
          (br $done)))
      (if (i32.lt_u (local.get $c) (i32.const 32))
        (then
          (if (i32.eq (local.get $c) (i32.const 10))
            (then (i32.store16 (local.get $o) (i32.const "\5cn")) (local.set $o (i32.add (local.get $o) (i32.const 2))) (br $done)))
          (if (i32.eq (local.get $c) (i32.const 13))
            (then (i32.store16 (local.get $o) (i32.const "\5cr")) (local.set $o (i32.add (local.get $o) (i32.const 2))) (br $done)))
          (if (i32.eq (local.get $c) (i32.const 9))
            (then (i32.store16 (local.get $o) (i32.const "\5ct")) (local.set $o (i32.add (local.get $o) (i32.const 2))) (br $done)))
          (i32.store (local.get $o) (i32.const "\5cu00"))
          (i32.store8 offset=4 (local.get $o) (i32.add (i32.const "0") (i32.shr_u (local.get $c) (i32.const 4))))
          (i32.store8 offset=5 (local.get $o) (i32.add (i32.and (local.get $c) (i32.const 15))
            (select (i32.const 87) (i32.const 48) (i32.ge_u (i32.and (local.get $c) (i32.const 15)) (i32.const 10)))))
          (local.set $o (i32.add (local.get $o) (i32.const 6)))
          (br $done)))
      (i32.store8 (local.get $o) (local.get $c))
      (local.set $o (i32.add (local.get $o) (i32.const 1))))
    (global.set $out (local.get $o)))

  ;; Write [$p, $e) as JSON string bytes, decoding entity references when
  ;; $entities is set.
  (func $jsonText (param $p i32) (param $e i32) (param $entities i32)
    (local $n i32)
    (local $v i32)
    (local $ve i32)
    (block $done
      (loop $l
        (br_if $done (i32.ge_u (local.get $p) (local.get $e)))
        (if (i32.and (local.get $entities) (i32.eq (i32.load8_u (local.get $p)) (i32.const "&")))
          (then
            (local.set $n (call $entityMatch (local.get $p) (local.get $e)))
            (if (local.get $n)
              (then
                (local.set $v (global.get $entVal))
                (local.set $ve (i32.add (local.get $v) (global.get $entLen)))
                (loop $value
                  (if (i32.lt_u (local.get $v) (local.get $ve))
                    (then
                      (call $jsonByte (i32.load8_u (local.get $v)))
                      (local.set $v (i32.add (local.get $v) (i32.const 1)))
                      (br $value))))
                (local.set $p (i32.add (local.get $p) (local.get $n)))
                (br $l)))))
        (call $jsonByte (i32.load8_u (local.get $p)))
        (local.set $p (i32.add (local.get $p) (i32.const 1)))
        (br $l))))

  (func $isAttrSpace (param $c i32) (result i32)
    (i32.or (call $isSpaceByte (local.get $c))
      (i32.or (i32.eq (local.get $c) (i32.const 10)) (i32.eq (local.get $c) (i32.const 13)))))

  ;; Attributes `{a="x" b='y' c=z bare}` at $p, before $e: returns the end
  ;; past `}`, or 0. With $write, writes them as an escaped JSON object into
  ;; reserved output.
  (func $dirAttrs (param $p i32) (param $e i32) (param $write i32) (result i32)
    (local $c i32)
    (local $k i32)
    (local $v i32)
    (local $q i32)
    (local $first i32)
    (if (i32.ge_u (local.get $p) (local.get $e)) (then (return (i32.const 0))))
    (if (i32.ne (i32.load8_u (local.get $p)) (i32.const "{")) (then (return (i32.const 0))))
    (if (local.get $write) (then (call $outByte (i32.const "{"))))
    (local.set $first (i32.const 1))
    (local.set $p (i32.add (local.get $p) (i32.const 1)))
    (block $fail
      (loop $attr
        (loop $space
          (br_if $fail (i32.ge_u (local.get $p) (local.get $e)))
          (if (call $isAttrSpace (i32.load8_u (local.get $p)))
            (then
              (local.set $p (i32.add (local.get $p) (i32.const 1)))
              (br $space))))
        (local.set $c (i32.load8_u (local.get $p)))
        (if (i32.eq (local.get $c) (i32.const "}"))
          (then
            (if (local.get $write) (then (call $outByte (i32.const "}"))))
            (return (i32.add (local.get $p) (i32.const 1)))))
        ;; the key
        (br_if $fail (i32.eqz (i32.or (call $isAlpha (local.get $c))
          (i32.or (i32.eq (local.get $c) (i32.const "_")) (i32.eq (local.get $c) (i32.const ":"))))))
        (local.set $k (local.get $p))
        (block $keyEnd
          (loop $key
            (local.set $p (i32.add (local.get $p) (i32.const 1)))
            (br_if $keyEnd (i32.ge_u (local.get $p) (local.get $e)))
            (local.set $c (i32.load8_u (local.get $p)))
            (br_if $key (i32.or (call $isAlnum (local.get $c))
              (i32.or (i32.or (i32.eq (local.get $c) (i32.const "_")) (i32.eq (local.get $c) (i32.const ":")))
                (i32.or (i32.eq (local.get $c) (i32.const ".")) (i32.eq (local.get $c) (i32.const "-"))))))))
        (if (local.get $write)
          (then
            (if (i32.eqz (local.get $first)) (then (call $outByte (i32.const ","))))
            (out.str "&quot;")
            (call $jsonText (local.get $k) (local.get $p) (i32.const 0))
            (out.str "&quot;:&quot;")))
        (local.set $first (i32.const 0))
        ;; an optional value
        (local.set $q (call $skipSpace (local.get $p) (local.get $e)))
        (if (i32.and (i32.lt_u (local.get $q) (local.get $e))
              (i32.eq (i32.load8_u (local.get $q)) (i32.const "=")))
          (then
            (local.set $p (call $skipSpace (i32.add (local.get $q) (i32.const 1)) (local.get $e)))
            (br_if $fail (i32.ge_u (local.get $p) (local.get $e)))
            (local.set $c (i32.load8_u (local.get $p)))
            (if (i32.or (i32.eq (local.get $c) (i32.const 34)) (i32.eq (local.get $c) (i32.const "'")))
              (then
                (local.set $v (i32.add (local.get $p) (i32.const 1)))
                (local.set $p (local.get $v))
                (loop $quoted
                  (br_if $fail (i32.ge_u (local.get $p) (local.get $e)))
                  (if (i32.ne (i32.load8_u (local.get $p)) (local.get $c))
                    (then
                      (local.set $p (i32.add (local.get $p) (i32.const 1)))
                      (br $quoted))))
                (if (local.get $write) (then (call $jsonText (local.get $v) (local.get $p) (i32.const 1))))
                (local.set $p (i32.add (local.get $p) (i32.const 1))))
              (else
                (local.set $v (local.get $p))
                (block $valueEnd
                  (loop $bare
                    (br_if $valueEnd (i32.ge_u (local.get $p) (local.get $e)))
                    (local.set $c (i32.load8_u (local.get $p)))
                    (br_if $valueEnd (i32.or (call $isAttrSpace (local.get $c))
                      (i32.or (i32.or (i32.eq (local.get $c) (i32.const 34)) (i32.eq (local.get $c) (i32.const "'")))
                        (i32.or (i32.or (i32.eq (local.get $c) (i32.const "=")) (i32.eq (local.get $c) (i32.const "<")))
                          (i32.or (i32.or (i32.eq (local.get $c) (i32.const ">")) (i32.eq (local.get $c) (i32.const "\60")))
                            (i32.eq (local.get $c) (i32.const "}")))))))
                    (local.set $p (i32.add (local.get $p) (i32.const 1)))
                    (br $bare)))
                (br_if $fail (i32.eq (local.get $p) (local.get $v)))
                (if (local.get $write) (then (call $jsonText (local.get $v) (local.get $p) (i32.const 1))))))))
        (if (local.get $write) (then (out.str "&quot;")))
        ;; attributes are separated by whitespace
        (br_if $fail (i32.ge_u (local.get $p) (local.get $e)))
        (local.set $c (i32.load8_u (local.get $p)))
        (br_if $fail (i32.eqz (i32.or (call $isAttrSpace (local.get $c)) (i32.eq (local.get $c) (i32.const "}")))))
        (br $attr)))
    (i32.const 0))

  ;; `::name[label]{attrs}` alone on the line [$p, $e): the end of the
  ;; directive before trailing space, or 0.
  (func $scanLeafDirective (param $p i32) (param $e i32) (result i32)
    (local $q i32)
    (local $t i32)
    (if (i32.ne (i32.load8_u offset=1 (local.get $p)) (i32.const ":")) (then (return (i32.const 0))))
    (local.set $q (call $dirNameEnd (i32.add (local.get $p) (i32.const 2)) (local.get $e)))
    (if (i32.eqz (call $directiveListed (i32.add (local.get $p) (i32.const 2)) (local.get $q)))
      (then (return (i32.const 0))))
    (if (i32.and (i32.lt_u (local.get $q) (local.get $e)) (i32.eq (i32.load8_u (local.get $q)) (i32.const "[")))
      (then
        (local.set $t (call $labelClose (local.get $q) (local.get $e)))
        (if (i32.eqz (local.get $t)) (then (return (i32.const 0))))
        (local.set $q (i32.add (local.get $t) (i32.const 1)))))
    (if (i32.and (i32.lt_u (local.get $q) (local.get $e)) (i32.eq (i32.load8_u (local.get $q)) (i32.const "{")))
      (then
        (local.set $q (call $dirAttrs (local.get $q) (local.get $e) (i32.const 0)))
        (if (i32.eqz (local.get $q)) (then (return (i32.const 0))))))
    (if (i32.lt_u (call $skipSpace (local.get $q) (local.get $e)) (local.get $e)) (then (return (i32.const 0))))
    (local.get $q))

  ;; Open a directive element: `<span` or `<div` with data-directive (the
  ;; name in [$nameB, $nameE)), data-attributes (attributes at $attrB, or
  ;; none when 0), and a source position. Leaf ranges are absolute; text
  ;; ranges are content offsets, resolved after reserving output.
  (func $htmlDirectiveOpen (param $div i32) (param $nameB i32) (param $nameE i32)
      (param $attrB i32) (param $attrE i32) (param $spB i32) (param $spE i32)
    (local $base i32)
    (if (i32.eqz (local.get $div))
      (then
        (local.set $spB (call $srcOffset (local.get $spB)))
        (local.set $spE (call $srcOffset (local.get $spE)))))
    (call $ensureOut (i32.add (i32.add (i32.sub (local.get $nameE) (local.get $nameB))
      (i32.mul (select (i32.sub (local.get $attrE) (local.get $attrB)) (i32.const 0) (local.get $attrB))
        (i32.const 8))) (i32.const 160)))
    (local.set $base (select (i32.const 0) (global.get $contentBase) (local.get $div)))
    (if (local.get $div)
      (then (out.str "<div data-directive=\22"))
      (else (out.str "<span data-directive=\22")))
    (call $outCopy (i32.add (local.get $base) (local.get $nameB)) (i32.add (local.get $base) (local.get $nameE)))
    (out.str "\22 data-attributes=\22")
    (if (local.get $attrB)
      (then (drop (call $dirAttrs (i32.add (local.get $base) (local.get $attrB))
        (i32.add (local.get $base) (local.get $attrE)) (i32.const 1))))
      (else (out.str "{}")))
    (call $outByte (i32.const 34))
    (if (i32.and (global.get $ext) (i32.const 32))
      (then (call $outSourcePos (local.get $spB) (local.get $spE))))
    (call $outByte (i32.const ">")))

  ;; A text directive mark: its opener, its closer, or one without a label.
  ;; Alt text keeps only the label.
  (func $renderDirectiveMark (param $m i32) (param $t i32) (param $b i32) (param $e i32)
    (local $close i32)
    (local $q i32)
    (if (i32.or (global.get $mode) (global.get $plain)) (then (return)))
    (if (i32.eq (local.get $t) (enum.get $Mk.dirclose))
      (then (out.str "</span>") (return)))
    (if (i32.eq (local.get $t) (enum.get $Mk.diropen))
      (then
        (local.set $close (call $slotAt (i32.load offset=$M.data (local.get $m))))
        (local.set $q (i32.add (i32.load offset=$M.beg (local.get $close)) (i32.const 1)))
        (call $htmlDirectiveOpen (i32.const 0)
          (i32.add (local.get $b) (i32.const 1)) (i32.sub (local.get $e) (i32.const 1))
          (select (local.get $q) (i32.const 0)
            (i32.lt_u (local.get $q) (i32.load offset=$M.end (local.get $close))))
          (i32.load offset=$M.end (local.get $close))
          (local.get $b) (i32.load offset=$M.end (local.get $close)))
        (return)))
    (local.set $q (i32.sub (call $dirNameEnd
      (i32.add (global.get $contentBase) (i32.add (local.get $b) (i32.const 1)))
      (i32.add (global.get $contentBase) (local.get $e))) (global.get $contentBase)))
    (call $htmlDirectiveOpen (i32.const 0) (i32.add (local.get $b) (i32.const 1)) (local.get $q)
      (select (local.get $q) (i32.const 0) (i32.lt_u (local.get $q) (local.get $e)))
      (local.get $e) (local.get $b) (local.get $e))
    (out.str "</span>"))

  ;; A leaf directive record: its label renders as inline content.
  (func $htmlLeafDirective (param $r i32)
    (local $p i32)
    (local $e i32)
    (local $q i32)
    (local $lb i32)
    (local $le i32)
    (local $line i32)
    (local.set $line (call $lineAt (local.get $r) (i32.const 0)))
    (local.set $p (call $lineBeg (local.get $line)))
    (local.set $e (call $lineEndOf (local.get $line)))
    (local.set $q (call $dirNameEnd (i32.add (local.get $p) (i32.const 2)) (local.get $e)))
    (local.set $lb (local.get $q))
    (local.set $le (local.get $q))
    (if (i32.and (i32.lt_u (local.get $q) (local.get $e)) (i32.eq (i32.load8_u (local.get $q)) (i32.const "[")))
      (then
        (local.set $lb (i32.add (local.get $q) (i32.const 1)))
        (local.set $le (call $labelClose (local.get $q) (local.get $e)))
        (local.set $q (i32.add (local.get $le) (i32.const 1)))))
    (call $cr)
    (call $htmlDirectiveOpen (i32.const 1) (i32.add (local.get $p) (i32.const 2))
      (call $dirNameEnd (i32.add (local.get $p) (i32.const 2)) (local.get $e))
      (select (local.get $q) (i32.const 0) (i32.lt_u (local.get $q) (local.get $e)))
      (local.get $e) (local.get $p) (local.get $e))
    (if (i32.gt_u (local.get $le) (local.get $lb))
      (then
        (global.set $scratchUsed (i32.const 0))
        (global.set $scratchTailUsed (i32.const 0))
        (global.set $contentBase (local.get $lb))
        (global.set $contentLen (i32.sub (local.get $le) (local.get $lb)))
        (global.set $contentInputEnd (local.get $le))
        (global.set $contentRec (local.get $r))
        (global.set $singleLineContent (i32.const 1))
        (call $inlineScan)
        (call $walkInlines)))
    (out.str "</div>\n"))
)
