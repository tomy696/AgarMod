'use strict';

// =============================================================================
// protocol.js - Raw protobuf wire-format message building/parsing for Agar.io
//
// Since we don't have the exact .proto definitions, this module builds and
// parses messages using raw protobuf wire-format encoding. The envelope
// structure is:
//   envelope { req message = 1; }
//   req { req_type_enum type = 1; <specific fields per type> }
// =============================================================================

// ---------------------------------------------------------------------------
// Protobuf wire-format primitives
// ---------------------------------------------------------------------------

/**
 * Encode an unsigned integer as a varint.
 * @param {number} value
 * @returns {Buffer}
 */
function encodeVarint(value) {
  const bytes = [];
  value = value >>> 0; // ensure unsigned 32-bit
  while (value > 0x7f) {
    bytes.push((value & 0x7f) | 0x80);
    value >>>= 7;
  }
  bytes.push(value & 0x7f);
  return Buffer.from(bytes);
}

/**
 * Encode a signed 32-bit integer using zigzag encoding (sint32).
 * @param {number} value
 * @returns {Buffer}
 */
function encodeSint32(value) {
  const zigzag = (value << 1) ^ (value >> 31);
  return encodeVarint(zigzag >>> 0);
}

/**
 * Decode a varint from a buffer at the given offset.
 * @param {Buffer} buf
 * @param {number} offset
 * @returns {{ value: number, bytesRead: number }}
 */
function decodeVarint(buf, offset) {
  let value = 0;
  let shift = 0;
  let bytesRead = 0;
  let byte;
  do {
    if (offset + bytesRead >= buf.length) {
      throw new Error('varint overflows buffer');
    }
    byte = buf[offset + bytesRead];
    value |= (byte & 0x7f) << shift;
    shift += 7;
    bytesRead++;
  } while (byte & 0x80);
  return { value: value >>> 0, bytesRead };
}

/**
 * Decode a zigzag-encoded sint32.
 * @param {number} n - The raw varint value.
 * @returns {number}
 */
function decodeSint32(n) {
  return (n >>> 1) ^ -(n & 1);
}

/**
 * Encode a float as a 4-byte little-endian buffer.
 * @param {number} value
 * @returns {Buffer}
 */
function encodeFloat(value) {
  const buf = Buffer.alloc(4);
  buf.writeFloatLE(value, 0);
  return buf;
}

/**
 * Encode a double as an 8-byte little-endian buffer.
 * @param {number} value
 * @returns {Buffer}
 */
function encodeDouble(value) {
  const buf = Buffer.alloc(8);
  buf.writeDoubleLE(value, 0);
  return buf;
}

/**
 * Build a protobuf field tag.
 * @param {number} fieldNumber
 * @param {number} wireType - 0=varint, 1=64-bit, 2=length-delimited, 5=32-bit
 * @returns {Buffer}
 */
function encodeTag(fieldNumber, wireType) {
  return encodeVarint((fieldNumber << 3) | wireType);
}

/**
 * Wrap data as a length-delimited field.
 * @param {number} fieldNumber
 * @param {Buffer} data
 * @returns {Buffer}
 */
function encodeLengthDelimited(fieldNumber, data) {
  return Buffer.concat([
    encodeTag(fieldNumber, 2),
    encodeVarint(data.length),
    data,
  ]);
}

/**
 * Encode a varint field.
 * @param {number} fieldNumber
 * @param {number} value
 * @returns {Buffer}
 */
function encodeVarintField(fieldNumber, value) {
  return Buffer.concat([encodeTag(fieldNumber, 0), encodeVarint(value)]);
}

/**
 * Encode a float field (wire type 5 = 32-bit).
 * @param {number} fieldNumber
 * @param {number} value
 * @returns {Buffer}
 */
function encodeFloatField(fieldNumber, value) {
  return Buffer.concat([encodeTag(fieldNumber, 5), encodeFloat(value)]);
}

/**
 * Encode a string field.
 * @param {number} fieldNumber
 * @param {string} str
 * @returns {Buffer}
 */
function encodeStringField(fieldNumber, str) {
  const strBuf = Buffer.from(str, 'utf8');
  return encodeLengthDelimited(fieldNumber, strBuf);
}

// ---------------------------------------------------------------------------
// Protobuf wire-format parser
// ---------------------------------------------------------------------------

/**
 * Parse all fields from a protobuf-encoded buffer.
 * Returns an array of { fieldNumber, wireType, value } objects.
 * For varint fields, value is a number.
 * For length-delimited fields, value is a Buffer.
 * For 32-bit fields, value is a Buffer (4 bytes).
 * For 64-bit fields, value is a Buffer (8 bytes).
 * @param {Buffer} buf
 * @returns {Array<{ fieldNumber: number, wireType: number, value: any }>}
 */
function parseFields(buf) {
  const fields = [];
  let offset = 0;
  while (offset < buf.length) {
    const tagResult = decodeVarint(buf, offset);
    offset += tagResult.bytesRead;
    const wireType = tagResult.value & 0x07;
    const fieldNumber = tagResult.value >>> 3;

    let value;
    switch (wireType) {
      case 0: { // varint
        const vr = decodeVarint(buf, offset);
        offset += vr.bytesRead;
        value = vr.value;
        break;
      }
      case 1: { // 64-bit
        value = buf.slice(offset, offset + 8);
        offset += 8;
        break;
      }
      case 2: { // length-delimited
        const lenResult = decodeVarint(buf, offset);
        offset += lenResult.bytesRead;
        value = buf.slice(offset, offset + lenResult.value);
        offset += lenResult.value;
        break;
      }
      case 5: { // 32-bit
        value = buf.slice(offset, offset + 4);
        offset += 4;
        break;
      }
      default:
        throw new Error(`Unknown wire type ${wireType} at offset ${offset}`);
    }
    fields.push({ fieldNumber, wireType, value });
  }
  return fields;
}

/**
 * Get the first field with the given number from a parsed fields array.
 * @param {Array} fields
 * @param {number} num
 * @returns {object|null}
 */
function getField(fields, num) {
  return fields.find((f) => f.fieldNumber === num) || null;
}

/**
 * Get all fields with the given number.
 * @param {Array} fields
 * @param {number} num
 * @returns {Array}
 */
function getFields(fields, num) {
  return fields.filter((f) => f.fieldNumber === num);
}

// ---------------------------------------------------------------------------
// req_type_enum constants
// ---------------------------------------------------------------------------

const REQ_TYPE = {
  // Server -> Client
  OFFLINE_TLE_QUEST_STATE_RESPONSE: 1,
  GAME_LOBBY_QUEUE_UPDATE: 3,
  OFFER_BUNDLE_RESPONSE: 4,
  GAME_SESSION_HIGHEST_MASS: 5,
  USER_STATS_RESPONSE: 7,
  GAME_OVER: 8,
  CONFIGURATION_CHANGE: 13,
  POTIONS_UPDATE: 15,
  GAME_BATTLE_ROYALE_ARENA_PHASE: 16,
  UDP_HANDSHAKE: 21,
  WALLET_UPDATES: 22,
  USER_PARTY_MEMBERSHIP_UPDATE: 25,
  DAILY_REWARDS_STATE_UPDATE: 28,
  RECONNECT: 33,
  USER_PARTY_CREATE_RESPONSE: 37,
  LOGIN_RESPONSE: 42,
  ACTIVATE_BOOST_RESPONSE: 43,
  SERVER_GOING_OFFLINE: 44,
  GAME_ARENA_PARTY_LEADERBOARD_ENTRIES_UPDATES: 45,
  GAME_ENTER_RESPONSE: 52,
  GAME_CONTINUE_UPDATE_RESPONSE: 56,
  PURCHASE_WALLET_UPDATES: 58,
  USER_SEASON_STATE_RESPONSE: 59,
  INAPP_PURCHASE_RESPONSE: 67,
  NETWORK_MESSAGE_PING: 70,
  GAME_ARENA_EVENT: 72,
  DEVICE_TOKEN_UPDATE: 74,
  USER_FRIEND_LIST_UPDATE: 77,
  GAME_ARENA_CURRENT_SAFE_AREA: 78,
  CONTENT_MANAGEMENT_SYSTEM_UPDATE: 81,
  GAME_ARENA_PARTY_CELL_UPDATES: 82,
  AUTOMATION_REQUEST_UPDATE: 85,
  EMOJI_DISPLAY_RESPONSE: 87,
  GAME_JOINED: 88,
  GAME_ARENA_STATE: 90,
  REALM_UPGRADE_RESPONSE: 91,
  SOFT_PURCHASE_RESPONSE: 93,
  DISCONNECT: 97,
  USER_PARTY_JOIN_RESPONSE: 98,
  NO_PROPER_RESPONSE: 101,
  GAME_ARENA_LEADERBOARD: 102,
  USER_TIMED_EVENT_UPDATES: 103,
  PONG: 104,
  UPDATE_USER_SETTINGS_RESPONSE: 105,
  CONNECT_RESPONSE: 106,
  GAME_CONTINUE_UPDATE_REQUEST: 111,
  GAME_CONTINUE_INFO: 112,
  GAME_LOBBY_ENTER_RESPONSE: 113,
  LOGIN_HANDSHAKE_RESPONSE_ENCRYPTED: 120,
};

// Client -> Server action IDs (best-effort reconstruction from the binary).
// These are the req_type_enum values the client sets when sending messages.
// The exact numbers are inferred from the enum ordering and binary patterns.
const CLIENT_REQ_TYPE = {
  CONNECT_REQUEST: 200,
  LOGIN_HANDSHAKE_REQUEST: 201,
  LOGIN_REQUEST_ENCRYPTED: 202,
  LOGIN_REQUEST_V5: 203,
  GAME_ENTER_REQUEST: 210,
  GAME_LOBBY_ENTER_REQUEST: 211,
  GAME_ARENA_DIRECTION_VECTOR: 220,
  GAME_ARENA_PLAYER_SPLIT: 221,
  GAME_ARENA_PLAYER_SHOOT_MASS: 222,
  EMOJI_DISPLAY_REQUEST: 223,
  PING: 230,
  DISCONNECT: 240,
  USER_PARTY_JOIN_REQUEST: 250,
  UDP_HANDSHAKE: 260,
};

// ---------------------------------------------------------------------------
// Message builders (Client -> Server)
// ---------------------------------------------------------------------------

/**
 * Wrap an inner req message inside an envelope.
 * envelope { req message = 1; }
 * @param {Buffer} reqBuf - The encoded req message.
 * @returns {Buffer}
 */
function buildEnvelope(reqBuf) {
  return encodeLengthDelimited(1, reqBuf);
}

/**
 * Build a req message with a type enum and an inner payload.
 * req { req_type_enum type = 1; <inner message at a type-specific field> }
 * @param {number} typeEnum
 * @param {Buffer|null} innerPayload - The type-specific sub-message (optional).
 * @param {number} [innerField=2] - The field number for the inner payload.
 * @returns {Buffer}
 */
function buildReq(typeEnum, innerPayload, innerField = 2) {
  const parts = [encodeVarintField(1, typeEnum)];
  if (innerPayload && innerPayload.length > 0) {
    parts.push(encodeLengthDelimited(innerField, innerPayload));
  }
  return Buffer.concat(parts);
}

/**
 * Build a connect_request message.
 * Sent after login to establish the game connection.
 * @param {string} [token] - Optional server token.
 * @returns {Buffer}
 */
function buildConnectRequest(token) {
  // connect_request: field 1 = token (string)
  const inner = token ? encodeStringField(1, token) : Buffer.alloc(0);
  const req = buildReq(CLIENT_REQ_TYPE.CONNECT_REQUEST, inner);
  return buildEnvelope(req);
}

/**
 * Build a game_enter_request message.
 * @param {string} playerName - Display name.
 * @param {string} [skinId] - Skin identifier.
 * @param {string} [partyCode] - Party code to join.
 * @returns {Buffer}
 */
function buildGameEnterRequest(playerName, skinId, partyCode) {
  // game_enter_request:
  //   field 1 = player_name (string)
  //   field 2 = skin_id (string)
  //   field 3 = party_code (string)
  //   field 4 = game_mode (varint, 0 = classic)
  const parts = [];
  parts.push(encodeStringField(1, playerName || 'Bot'));
  if (skinId) parts.push(encodeStringField(2, skinId));
  if (partyCode) parts.push(encodeStringField(3, partyCode));
  parts.push(encodeVarintField(4, 0)); // classic mode
  const inner = Buffer.concat(parts);
  const req = buildReq(CLIENT_REQ_TYPE.GAME_ENTER_REQUEST, inner);
  return buildEnvelope(req);
}

/**
 * Build a game_arena_direction_vector message.
 * @param {number} x - Normalized X direction (-1 to 1).
 * @param {number} y - Normalized Y direction (-1 to 1).
 * @returns {Buffer}
 */
function buildDirectionVector(x, y) {
  // game_arena_direction_vector:
  //   field 1 = x (float)
  //   field 2 = y (float)
  const inner = Buffer.concat([
    encodeFloatField(1, x),
    encodeFloatField(2, y),
  ]);
  const req = buildReq(CLIENT_REQ_TYPE.GAME_ARENA_DIRECTION_VECTOR, inner);
  return buildEnvelope(req);
}

/**
 * Build a game_arena_player_split message.
 * @returns {Buffer}
 */
function buildPlayerSplit() {
  const req = buildReq(CLIENT_REQ_TYPE.GAME_ARENA_PLAYER_SPLIT, null);
  return buildEnvelope(req);
}

/**
 * Build a game_arena_player_shoot_mass (eject/feed) message.
 * @returns {Buffer}
 */
function buildShootMass() {
  const req = buildReq(CLIENT_REQ_TYPE.GAME_ARENA_PLAYER_SHOOT_MASS, null);
  return buildEnvelope(req);
}

/**
 * Build a ping message.
 * @returns {Buffer}
 */
function buildPing() {
  // ping: field 1 = timestamp (varint, ms)
  const inner = encodeVarintField(1, Date.now() % 0xffffffff);
  const req = buildReq(CLIENT_REQ_TYPE.PING, inner);
  return buildEnvelope(req);
}

/**
 * Build a disconnect message.
 * @returns {Buffer}
 */
function buildDisconnect() {
  const req = buildReq(CLIENT_REQ_TYPE.DISCONNECT, null);
  return buildEnvelope(req);
}

/**
 * Build a login_request_v5 message (simplified, no encryption).
 * This is a best-effort minimal login for bot clients.
 * @param {string} name - Player name.
 * @returns {Buffer}
 */
function buildLoginRequestV5(name) {
  // login_request_v5:
  //   field 1 = name (string)
  //   field 2 = client_version (string)
  //   field 3 = platform (string)
  const inner = Buffer.concat([
    encodeStringField(1, name || 'Bot'),
    encodeStringField(2, '2.25.4'), // approximate recent version
    encodeStringField(3, 'ios'),
  ]);
  const req = buildReq(CLIENT_REQ_TYPE.LOGIN_REQUEST_V5, inner);
  return buildEnvelope(req);
}

// ---------------------------------------------------------------------------
// Message parsers (Server -> Client)
// ---------------------------------------------------------------------------

/**
 * Parse a raw binary message from the server.
 * Returns { type, fields } where type is the req_type_enum and fields is the
 * parsed protobuf fields array of the inner message.
 * @param {Buffer} data
 * @returns {{ type: number, fields: Array, raw: Buffer }|null}
 */
function parseServerMessage(data) {
  try {
    const buf = Buffer.isBuffer(data) ? data : Buffer.from(data);
    // Outer envelope: field 1 = req (length-delimited)
    const envelopeFields = parseFields(buf);
    const reqField = getField(envelopeFields, 1);
    if (!reqField || reqField.wireType !== 2) {
      return null;
    }
    // Inner req: field 1 = req_type_enum (varint), remaining = message-specific
    const reqFields = parseFields(reqField.value);
    const typeField = getField(reqFields, 1);
    if (!typeField) return null;
    const type = typeField.value;
    return { type, fields: reqFields, raw: reqField.value };
  } catch (err) {
    return null;
  }
}

/**
 * Parse a connect_response message.
 * @param {Array} fields - Parsed fields from the req.
 * @returns {{ success: boolean, serverId: string|null }}
 */
function parseConnectResponse(fields) {
  // field 2 = inner connect_response
  const inner = getField(fields, 2);
  if (!inner || inner.wireType !== 2) {
    return { success: false, serverId: null };
  }
  const innerFields = parseFields(inner.value);
  // field 1 = success (varint bool)
  const successField = getField(innerFields, 1);
  // field 2 = server_id (string)
  const serverIdField = getField(innerFields, 2);
  return {
    success: successField ? !!successField.value : true,
    serverId: serverIdField ? serverIdField.value.toString('utf8') : null,
  };
}

/**
 * Parse a game_enter_response message.
 * @param {Array} fields
 * @returns {{ success: boolean, playerId: number|null }}
 */
function parseGameEnterResponse(fields) {
  const inner = getField(fields, 2);
  if (!inner || inner.wireType !== 2) {
    return { success: false, playerId: null };
  }
  const innerFields = parseFields(inner.value);
  const successField = getField(innerFields, 1);
  const playerIdField = getField(innerFields, 2);
  return {
    success: successField ? !!successField.value : true,
    playerId: playerIdField ? playerIdField.value : null,
  };
}

/**
 * Parse a game_joined message.
 * @param {Array} fields
 * @returns {{ arenaId: number|null, arenaWidth: number, arenaHeight: number }}
 */
function parseGameJoined(fields) {
  const inner = getField(fields, 2);
  if (!inner || inner.wireType !== 2) {
    return { arenaId: null, arenaWidth: 14142, arenaHeight: 14142 };
  }
  const innerFields = parseFields(inner.value);
  const arenaIdField = getField(innerFields, 1);
  const widthField = getField(innerFields, 2);
  const heightField = getField(innerFields, 3);
  return {
    arenaId: arenaIdField ? arenaIdField.value : null,
    arenaWidth: widthField ? widthField.value : 14142,
    arenaHeight: heightField ? heightField.value : 14142,
  };
}

/**
 * Parse a game_arena_state message.
 * Extracts cell states (appeared, changed, died, disappeared).
 * @param {Array} fields
 * @returns {{ cells: Array<object>, deaths: Array<number> }}
 */
function parseGameArenaState(fields) {
  const inner = getField(fields, 2);
  if (!inner || inner.wireType !== 2) {
    return { cells: [], deaths: [] };
  }
  const innerFields = parseFields(inner.value);

  const cells = [];
  const deaths = [];

  // game_arena_state contains repeated game_arena_cell_state (field 1 = appeared, 2 = changed)
  // and repeated game_arena_cell_death (field 3) and disappeared IDs (field 4)

  // Parse appeared cells (field 1, repeated length-delimited)
  const appearedFields = getFields(innerFields, 1);
  for (const f of appearedFields) {
    if (f.wireType === 2) {
      const cell = parseCellState(f.value);
      if (cell) {
        cell.event = 'appeared';
        cells.push(cell);
      }
    }
  }

  // Parse changed cells (field 2, repeated length-delimited)
  const changedFields = getFields(innerFields, 2);
  for (const f of changedFields) {
    if (f.wireType === 2) {
      const cell = parseCellState(f.value);
      if (cell) {
        cell.event = 'changed';
        cells.push(cell);
      }
    }
  }

  // Parse cell deaths (field 3, repeated length-delimited)
  const deathFields = getFields(innerFields, 3);
  for (const f of deathFields) {
    if (f.wireType === 2) {
      const deathInner = parseFields(f.value);
      const idField = getField(deathInner, 1);
      if (idField) deaths.push(idField.value);
    }
  }

  // Parse disappeared cells (field 4, repeated varint)
  const disappearedFields = getFields(innerFields, 4);
  for (const f of disappearedFields) {
    if (f.wireType === 0) {
      deaths.push(f.value);
    }
  }

  return { cells, deaths };
}

/**
 * Parse a single game_arena_cell_state.
 * @param {Buffer} buf
 * @returns {object|null}
 */
function parseCellState(buf) {
  try {
    const fields = parseFields(buf);
    // game_arena_cell_state:
    //   field 1 = cell_id (varint)
    //   field 2 = x (sint32 or float)
    //   field 3 = y (sint32 or float)
    //   field 4 = radius (float or varint)
    //   field 5 = owner_id (varint)
    //   field 6 = name (string)
    //   field 7 = skin_id (string)
    //   field 8 = flags (varint) - bit 0: is_virus, bit 1: is_food, etc.
    const idField = getField(fields, 1);
    const xField = getField(fields, 2);
    const yField = getField(fields, 3);
    const radiusField = getField(fields, 4);
    const ownerField = getField(fields, 5);
    const nameField = getField(fields, 6);
    const flagsField = getField(fields, 8);

    const cell = {
      id: idField ? idField.value : 0,
      x: 0,
      y: 0,
      radius: 0,
      ownerId: ownerField ? ownerField.value : 0,
      name: nameField && nameField.wireType === 2
        ? nameField.value.toString('utf8')
        : '',
      isVirus: false,
      isFood: false,
      isEjected: false,
    };

    // X and Y may be encoded as sint32 (varint wire type) or float (32-bit wire type)
    if (xField) {
      if (xField.wireType === 5) {
        cell.x = xField.value.readFloatLE(0);
      } else {
        cell.x = decodeSint32(xField.value);
      }
    }
    if (yField) {
      if (yField.wireType === 5) {
        cell.y = yField.value.readFloatLE(0);
      } else {
        cell.y = decodeSint32(yField.value);
      }
    }
    if (radiusField) {
      if (radiusField.wireType === 5) {
        cell.radius = radiusField.value.readFloatLE(0);
      } else {
        cell.radius = radiusField.value;
      }
    }

    if (flagsField) {
      cell.isVirus = !!(flagsField.value & 0x01);
      cell.isFood = !!(flagsField.value & 0x02);
      cell.isEjected = !!(flagsField.value & 0x04);
    }

    return cell;
  } catch (e) {
    return null;
  }
}

/**
 * Parse a game_arena_leaderboard message.
 * @param {Array} fields
 * @returns {{ entries: Array<{ position: number, name: string, id: number }>, playerPosition: number }}
 */
function parseLeaderboard(fields) {
  const inner = getField(fields, 2);
  if (!inner || inner.wireType !== 2) {
    return { entries: [], playerPosition: 0 };
  }
  const innerFields = parseFields(inner.value);

  const entries = [];
  // field 1 = repeated leaderboard_entry (length-delimited)
  const entryFields = getFields(innerFields, 1);
  for (const ef of entryFields) {
    if (ef.wireType === 2) {
      const entryInner = parseFields(ef.value);
      const posField = getField(entryInner, 1);
      const nameField = getField(entryInner, 2);
      const idField = getField(entryInner, 3);
      entries.push({
        position: posField ? posField.value : 0,
        name: nameField && nameField.wireType === 2
          ? nameField.value.toString('utf8')
          : '',
        id: idField ? idField.value : 0,
      });
    }
  }

  // field 2 = player_position (varint)
  const posField = getField(innerFields, 2);

  return {
    entries,
    playerPosition: posField ? posField.value : 0,
  };
}

/**
 * Parse a pong message.
 * @param {Array} fields
 * @returns {{ timestamp: number }}
 */
function parsePong(fields) {
  const inner = getField(fields, 2);
  if (!inner || inner.wireType !== 2) {
    return { timestamp: 0 };
  }
  const innerFields = parseFields(inner.value);
  const tsField = getField(innerFields, 1);
  return { timestamp: tsField ? tsField.value : 0 };
}

/**
 * Parse a login_response message (minimal extraction).
 * @param {Array} fields
 * @returns {{ success: boolean }}
 */
function parseLoginResponse(fields) {
  const inner = getField(fields, 2);
  if (!inner || inner.wireType !== 2) {
    return { success: false };
  }
  // The login_response is complex with many sub-fields.
  // For bot purposes, if we received it, login was successful.
  return { success: true };
}

// ---------------------------------------------------------------------------
// Exports
// ---------------------------------------------------------------------------

module.exports = {
  // Constants
  REQ_TYPE,
  CLIENT_REQ_TYPE,

  // Primitives
  encodeVarint,
  encodeSint32,
  decodeVarint,
  decodeSint32,
  encodeFloat,
  encodeDouble,
  encodeTag,
  encodeLengthDelimited,
  encodeVarintField,
  encodeFloatField,
  encodeStringField,
  parseFields,
  getField,
  getFields,

  // Builders
  buildEnvelope,
  buildReq,
  buildConnectRequest,
  buildGameEnterRequest,
  buildDirectionVector,
  buildPlayerSplit,
  buildShootMass,
  buildPing,
  buildDisconnect,
  buildLoginRequestV5,

  // Parsers
  parseServerMessage,
  parseConnectResponse,
  parseGameEnterResponse,
  parseGameJoined,
  parseGameArenaState,
  parseCellState,
  parseLeaderboard,
  parsePong,
  parseLoginResponse,
};
