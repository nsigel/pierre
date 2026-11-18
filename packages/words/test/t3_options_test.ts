import assert from 'node:assert/strict';
import test from 'node:test';

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
