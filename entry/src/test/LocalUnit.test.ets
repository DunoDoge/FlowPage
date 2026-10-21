import { describe, it, expect } from '@ohos/hypium';
import {
  CARD_FIELD_SEPARATOR,
  cardLineOf,
  cardTitleOf,
  parseCardLine,
  parseCardLines
} from '../main/ets/common/CardFormat';
import { HighlightSegment, highlightSegments } from '../main/ets/common/Highlight';
import { splitIntoChunks } from '../main/ets/common/TextUtil';

function joinedSegments(segments: HighlightSegment[]): string {
  let joined = '';
  for (let i = 0; i < segments.length; i++) {
    joined = joined + segments[i].text;
  }
  return joined;
}

export default function localUnitTest() {
  describe('LocalUnitTest', () => {
    it('encodesCardLineWithSeparatorSafeTitle', 0, () => {
      const line = cardLineOf('标\u0001题\n第二行', 'example.com', 'id-1');
      expect(line.indexOf(CARD_FIELD_SEPARATOR)).assertLarger(0);
      expect(line.indexOf('\u0001')).assertEqual(-1);
      expect(line.indexOf('\n')).assertEqual(-1);
      const parsed = parseCardLine(line);
      expect(parsed === undefined).assertFalse();
      if (parsed !== undefined) {
        expect(parsed.title).assertEqual('标 题 第二行');
        expect(parsed.domain).assertEqual('example.com');
        expect(parsed.id).assertEqual('id-1');
      }
      expect(cardTitleOf('a\r\nb')).assertEqual('a  b');
    });

    it('parsesMultipleCardLinesAndSkipsBrokenOnes', 0, () => {
      const raw = `${cardLineOf('甲', 'a.com', '1')}\nbroken\n${cardLineOf('乙', 'b.com', '2')}`;
      const items = parseCardLines(raw);
      expect(items.length).assertEqual(2);
      expect(items[0].id).assertEqual('1');
      expect(items[1].title).assertEqual('乙');
      expect(parseCardLines('').length).assertEqual(0);
      expect(parseCardLine('only-one-field') === undefined).assertTrue();
      const percentTitle = parseCardLine(cardLineOf('甲%01乙', 'a.com', '3'));
      expect(percentTitle === undefined).assertFalse();
      if (percentTitle !== undefined) {
        expect(percentTitle.title).assertEqual('甲%01乙');
      }
    });

    it('highlightsKeywordsCaseInsensitively', 0, () => {
      const first = highlightSegments('HarmonyOS harm', 'HARM');
      expect(joinedSegments(first)).assertEqual('HarmonyOS harm');
      let matched = 0;
      for (let i = 0; i < first.length; i++) {
        if (first[i].matched) {
          matched = matched + 1;
        }
      }
      expect(matched).assertEqual(2);
      expect(highlightSegments('', 'x').length).assertEqual(0);
      expect(highlightSegments('abc', '  ').length).assertEqual(1);
    });

    it('splitsTextIntoChunksWithoutDroppingContent', 0, () => {
      const chunks = splitIntoChunks('第一段\n\n第二段', 100);
      expect(chunks.length).assertEqual(1);
      expect(chunks[0].indexOf('第一段')).assertEqual(0);
      expect(chunks[0].indexOf('第二段')).assertLarger(0);
      const long = splitIntoChunks('aaaaaaaaaaaaaaaaaaaaaaaaa', 10);
      expect(long.length).assertEqual(3);
      expect(long[0].length).assertEqual(10);
      expect(long[2].length).assertEqual(5);
    });
  });
}
