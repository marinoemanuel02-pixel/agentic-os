import words from '../data/words.json';
import {LINES, SHOTS} from '../data/timeline';
import {FPS} from './look';
import {makeCues, type WordTimes} from './cue-core';
export const {cue, wordAt, lineEnd} = makeCues(words as WordTimes, LINES, SHOTS, FPS);
