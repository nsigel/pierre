import assert from 'node:assert/strict';
import test from 'node:test';

import { createHtmlRenderer } from '../dist/html.js';
import {
  createHtmlSession,
  type RenderOptions,
  renderToHtml,
} from '../dist/index.js';

const dec = new TextDecoder();
const html = (
  md: string,
  options: RenderOptions & { frontmatter?: false } = {}
) => dec.decode(renderToHtml(md, options));
const complete = (md: string, options?: RenderOptions) =>
  createHtmlSession().render(md, { ...options, incomplete: true }).html;

void test('singleTilde: false strikes only runs of two tildes', () => {
  const off = { singleTilde: false };
  assert.equal(
    html('~/path, ~one~ and ~~two~~ ~~~three~~~', off),
    '<p>~/path, ~one~ and <del>two</del> ~~~three~~~</p>\n'
  );
  assert.equal(html('~one~ ~a~~', off), '<p>~one~ ~a~~</p>\n');
  assert.equal(html('~~a~', off), '<p>~~a~</p>\n');
  assert.equal(html('~one~'), '<p><del>one</del></p>\n');
  assert.equal(html('~one~', { singleTilde: true }), '<p><del>one</del></p>\n');
  // completion closes only what the parser can strike
  assert.equal(complete('~~two', off), '<p><del>two</del></p>\n');
  assert.equal(complete('~one', off), '<p>~one</p>\n');
  assert.equal(complete('a ~one', { incomplete: true }), '<p>a ~one</p>\n');
});

void test('windowsPaths keeps the backslashes of drive path destinations', () => {
  const on = { windowsPaths: true };
  assert.equal(
    html(String.raw`[x](C:\me\.t3\a.png) [y](C:/a\_b) [z](\\host\.x)`, on),
    '<p><a href="C:%5Cme%5C.t3%5Ca.png">x</a> <a href="C:/a%5C_b">y</a> ' +
      '<a href="%5Chost.x">z</a></p>\n'
  );
  assert.equal(
    html(String.raw`[x](C:\me\.t3\a.png)`),
    '<p><a href="C:%5Cme.t3%5Ca.png">x</a></p>\n'
  );
  // entity references still decode once
  for (const prefix of ['', '!']) {
    assert.match(
      html(`${prefix}[s](<C:\\R&amp;D folder\\.t3\\s.png>)`, on),
      /="C:%5CR&amp;D%20folder%5C.t3%5Cs.png"/
    );
  }
  assert.equal(
    html('[r]\n\n[r]: <C:\\work\\&amp;lt;\\.t3\\s.png>', on),
    '<p><a href="C:%5Cwork%5C&amp;lt;%5C.t3%5Cs.png">r</a></p>\n'
  );
});

void test('windowsPaths keeps escapes inside prose drive paths', () => {
  const on = { windowsPaths: true };
  assert.equal(
    html(String.raw`C:\Users\me\.t3 and "C:\" and C:\x and \*this\*`, on),
    String.raw`<p>C:\Users\me\.t3 and &quot;C:\&quot; and C:\x and *this*</p>` +
      '\n'
  );
  assert.equal(
    html(
      String.raw`one\_two C:\a\_b \*x\* *em*E:\e\_f \*z\* x:\\y a:\&amp;`,
      on
    ),
    String.raw`<p>one_two C:\a\_b *x* <em>em</em>E:\e\_f *z* x:\\y a:\&amp;amp;</p>` +
      '\n'
  );
  // a word character before the letter, or another word, is no drive
  assert.equal(
    html(String.raw`ab:\_c C: \_d`, on),
    String.raw`<p>ab:_c C: _d</p>` + '\n'
  );
  for (const space of [' ', '\t', '\u00a0', '\u2003', '\u202f', '\ufeff']) {
    assert.equal(
      html(String.raw`C:\me\_b${space}\*x\*`, on),
      String.raw`<p>C:\me\_b${space}*x*</p>` + '\n'
    );
  }
  assert.equal(
    html(String.raw`C:\Users\me\.t3`),
    String.raw`<p>C:\Users\me.t3</p>` + '\n'
  );
});

void test('codeMeta puts the info string after the language on <code>', () => {
  const on = { codeMeta: true };
  const source = '```ts  title="x" \\* &amp;  \n1\n```\n\n```ts\n2\n```\n';
  assert.equal(
    html(source, on),
    '<pre><code class="language-ts" data-meta="title=&quot;x&quot; * &amp;">1\n' +
      '</code></pre>\n<pre><code class="language-ts">2\n</code></pre>\n'
  );
  assert.doesNotMatch(html(source), /data-meta/);
  assert.match(
    createHtmlSession().render('```ts title="x"\n1', on).html,
    /<code class="language-ts" data-meta="title=&quot;x&quot;">/
  );
  const formatted = createHtmlRenderer(on).render(source, false).html;
  assert.match(
    formatted,
    /<code data-markdown="code" class="language-ts" data-meta="title=&quot;x&quot; \* &amp;">/
  );
  assert.equal(formatted.match(/data-meta/g)?.length, 1);
});

/** Each element with a source position, and the source bytes it covers. */
function spans(source: string, output: string): string[] {
  const bytes = new TextEncoder().encode(source);
  return [...output.matchAll(/<(\w+)[^>]*?data-sourcepos="(\d+)-(\d+)"/g)].map(
    ([, tag, start, end]) =>
      `${tag} ${dec.decode(bytes.slice(Number(start), Number(end)))}`
  );
}

void test('sourcePositions marks list items, links, images, and code', () => {
  const on = { sourcePositions: true };
  const source = [
    '- ü [l](u) <http://x.y> www.z.com ![i](p "t") [r]',
    '- b',
    '',
    '  ```js',
    '  x',
    '  ```  ',
    '- # h ##',
    '> 1. q',
    '>    lazy',
    '',
    '[r]: /v',
    '',
    '|[a](b) \\| [c](d)|',
    '|-|',
    '',
    '-',
    '',
    '    indented',
    '    code',
    '',
    '```',
    'open',
  ].join('\n');
  assert.deepEqual(spans(source, html(source, on)), [
    'li - ü [l](u) <http://x.y> www.z.com ![i](p "t") [r]',
    'a [l](u)',
    'a <http://x.y>',
    'a www.z.com',
    'img ![i](p "t")',
    'a [r]',
    'li - b\n\n  ```js\n  x\n  ```  ',
    'pre ```js\n  x\n  ```  ',
    'li - # h ##',
    'li 1. q\n>    lazy',
    'a [a](b)',
    'a [c](d)',
    'li -',
    'pre     indented\n    code',
    'pre ```\nopen',
  ]);
  assert.doesNotMatch(html(source), /data-sourcepos/);
  // raw HTML passes through untouched
  assert.equal(html('<a href="x">y</a>', on), '<p><a href="x">y</a></p>\n');
});

void test('sourcePositions count from the start of a session', () => {
  const on = { sourcePositions: true };
  const source =
    'ü [a](b)\n\n- x [c](d)\n\nmore\n\n```ts\nline\n```\n\nend [e](f)\n';
  const session = createHtmlSession();
  let last = '';
  for (let i = 1; i <= source.length; i++)
    last = session.render(source.slice(0, i), on).html;
  assert.equal(last, html(source, on));
  // an open fence grows its position as it streams
  const fence = createHtmlSession();
  fence.render('```\na', on);
  assert.deepEqual(spans('```\nab', fence.render('```\nab', on).html), [
    'pre ```\nab',
  ]);
  const formatted = createHtmlRenderer(on).render(source, false).html;
  assert.deepEqual(spans(source, formatted), spans(source, last));
});

const attributes = (output: string): unknown[] =>
  [...output.matchAll(/data-attributes="([^"]*)"/g)].map(([, value]) =>
    JSON.parse(
      value
        .replaceAll('&quot;', '"')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&amp;', '&')
    )
  );

void test('directives renders the listed text and leaf directives', () => {
  const on = {
    directives: ['codex-file-citation', 'codex-followup', 'artifact-template'],
  };
  assert.equal(
    html(
      'See :codex-file-citation[**a** `b`]{path="/a/b.ts" line_start="3" line_end="5"} ' +
        'and :codex-followup[Do it]{prompt="Run the tests"}.',
      on
    ),
    '<p>See <span data-directive="codex-file-citation" data-attributes="' +
      '{&quot;path&quot;:&quot;/a/b.ts&quot;,&quot;line_start&quot;:&quot;3&quot;,' +
      '&quot;line_end&quot;:&quot;5&quot;}"><strong>a</strong> <code>b</code></span> ' +
      'and <span data-directive="codex-followup" data-attributes="' +
      '{&quot;prompt&quot;:&quot;Run the tests&quot;}">Do it</span>.</p>\n'
  );
  assert.equal(
    html(
      'para\n::artifact-template{name="x" kind="y"}  \n- ::artifact-template[*l*]',
      on
    ),
    '<p>para</p>\n<div data-directive="artifact-template" data-attributes="' +
      '{&quot;name&quot;:&quot;x&quot;,&quot;kind&quot;:&quot;y&quot;}"></div>\n' +
      '<ul>\n<li>\n<div data-directive="artifact-template" data-attributes="{}">' +
      '<em>l</em></div>\n</li>\n</ul>\n'
  );
  // unlisted names, other text after a leaf, and the option off stay text
  for (const source of [
    ':other[a] ::artifact-template',
    '::artifact-template{name="x"} trailing',
    'a::codex-followup 10:30',
  ])
    assert.equal(
      html(source, on),
      `<p>${source.replaceAll('"', '&quot;')}</p>\n`
    );
  assert.equal(
    html(':codex-followup[a]{b="c"}'),
    '<p>:codex-followup[a]{b=&quot;c&quot;}</p>\n'
  );
});

void test('directives parse attributes and labels as remark-directive does', () => {
  const on = { directives: ['x'] };
  const output = html(
    ':x :x{a=1 b} :x{ c = "2" } :x{q=\'it"s &amp; <b>\'} :x{n="d\ne\u0001"} :x{bad"} :x[open',
    on
  );
  assert.deepEqual(attributes(output), [
    {},
    { a: '1', b: '' },
    { c: '2' },
    { q: 'it"s & <b>' },
    { n: 'd\ne\u0001' },
    {},
    {},
  ]);
  assert.match(output, /<\/span>\{bad&quot;\} <span[^>]*><\/span>\[open<\/p>/);
  // a label may hold brackets and links, but a name ends at a letter
  assert.equal(
    html(':x[[n] [l](u)] :xé', on),
    '<p><span data-directive="x" data-attributes="{}">[n] <a href="u">l</a></span> :xé</p>\n'
  );
});

void test('directives carry source positions and stream', () => {
  const on = {
    directives: ['codex-file-citation', 'artifact-template'],
    sourcePositions: true,
  };
  const source =
    'Intro :codex-file-citation[x]{path="/a"} :codex-file-citation\n\n' +
    '::artifact-template{name="x"}\n\nend\n';
  assert.deepEqual(spans(source, html(source, on)), [
    'span :codex-file-citation[x]{path="/a"}',
    'span :codex-file-citation',
    'div ::artifact-template{name="x"}',
  ]);
  for (const incomplete of [false, true]) {
    const session = createHtmlSession();
    let last = '';
    for (let i = 1; i <= source.length; i++)
      last = session.render(source.slice(0, i), { ...on, incomplete }).html;
    assert.equal(last, html(source, on));
  }
  assert.deepEqual(
    spans(source, createHtmlRenderer(on).render(source, false).html),
    spans(source, html(source, on))
  );
});

void test('directive names share the id prefix room', () => {
  const names = ['n'.repeat(200)];
  assert.throws(
    () =>
      createHtmlRenderer({
        idPrefix: 'p'.repeat(4000),
        directives: names,
      }).render(`:${names[0]}`, false),
    RangeError
  );
  // the names change between renders, and a long prefix fits without them
  assert.match(
    html(`:${names[0]}`, { directives: names }),
    /<span data-directive/
  );
  assert.equal(html(':n', { directives: ['m'] }), '<p>:n</p>\n');
  assert.match(
    createHtmlRenderer({ idPrefix: 'p'.repeat(4000) }).render(
      '[^1]\n\n[^1]: x',
      false
    ).html,
    /pppp/
  );
});

void test('escapeHtml writes raw HTML as escaped text', () => {
  const on = { escapeHtml: true };
  assert.equal(
    html('a <b>x</b> & <img src=y onerror=z> `<i>`', on),
    '<p>a &lt;b&gt;x&lt;/b&gt; &amp; &lt;img src=y onerror=z&gt; <code>&lt;i&gt;</code></p>\n'
  );
  assert.equal(
    html('<details>\n<summary>s</summary>\n\n**md**\n</details>', on),
    '&lt;details&gt;\n&lt;summary&gt;s&lt;/summary&gt;\n<p><strong>md</strong></p>\n&lt;/details&gt;\n'
  );
  // autolinks are not raw HTML
  assert.equal(html('<https://a.dev>', on), '<p><a href="https://a.dev">https://a.dev</a></p>\n');
  assert.equal(html('a <b>x</b>'), '<p>a <b>x</b></p>\n');
});
