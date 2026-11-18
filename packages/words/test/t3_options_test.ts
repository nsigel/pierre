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
