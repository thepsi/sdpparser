/** Developed according to https://tools.ietf.org/html/rfc4566 */

{
var jsCommon = require("jscommon");
var utils = require("./utils");
var guessType = jsCommon.guessType;

/** The offset of the NTP time compared to Unix time. */
var NTP_OFFSET = 2208988800;

var aggregateSdpProperties = function(sdpProperties) {
	var sdp = {};
	var obj = sdp;
	for (var i = 0; i < sdpProperties.length; i++) {
		for (var p in sdpProperties[i]) {
			if (sdpProperties[i].hasOwnProperty(p)) {
				if (options.useMediaSections !== false && p == utils.SDP_TYPES["m"]) {
					obj = sdp;
				}
				if (obj[p]) {
					if (!obj[p].push) {
						obj[p] = [obj[p]];
					}
					obj[p].push(sdpProperties[i][p]);
				} else {
					obj[p] = sdpProperties[i][p];
				}
				if (options.useMediaSections !== false && p == utils.SDP_TYPES["m"]) {
					obj = sdpProperties[i][p];
				}
			}
		}
	}
	return sdp;
};

var aggregateSdp = function(sdpProperties) {
	var sdp = aggregateSdpProperties(sdpProperties);
	// ensure that media is an array
	if (sdp.media && !sdp.media.join) {
		sdp.media = [sdp.media];
	}

	// aggregate payloads in each media section
	if (options.aggregatePayloads !== false) {
		aggregatePayloads(sdp);
	}
	return sdp;
};

var aggregate = aggregateSdp;

var aggregatePayloads = function(sdp) {
	if (!sdp.media || !sdp.media.length) {
		return sdp;
	}
	for (var i = 0; i < sdp.media.length; i++) {
		var m = sdp.media[i];
		if (!m.payloads) {
			continue;
		}
		var payloads = [];
		for (var j = 0; j < m.payloads.length; j++) {
			var payload = {id: m.payloads[j]};
			aggregatePayloadAttribute(payload, m, "rtp");
			aggregatePayloadAttribute(payload, m, "fmtp");
			payloads[j] = payload;
		}
		if (m.rtp) {
			delete m.rtp;
		}
		if (m.fmtp) {
			delete m.fmtp;
		}
		m.payloads = payloads;
	}
	return sdp;
};

var aggregatePayloadAttribute = function(payload, media, attr) {
	if (media[attr] && !media[attr].push) {
		media[attr] = [media[attr]];
	}
	if (media[attr]) {
		payload[attr] = getPayload(media[attr], payload.id);
	}
	if (payload[attr]) {
		delete payload[attr].payload;
	} else {
		delete payload[attr];
	}
};

var getPayload = function(payloads, id) {
	if (payloads.payload === id) {
		return payloads;
	}
	for (var i = 0; i < payloads.length; i++) {
		if (payloads[i].payload === id) {
			return payloads[i];
		}
	}
	return null;
};

var OUTPUT_ORDER = ["v", "o", "s", "i", "u", "e", "p", "c", "b", "t", "r", "z", "k", "a", "*", "m"];
var getOutputOrder = function(order, property) {
	var idx = order.indexOf(property);
	if (idx < 0) {
		idx = order.indexOf(utils.SDP_TYPES[property]);
	}
	if (idx < 0) {
		idx = order.indexOf("*");
	}
	if (idx < 0) {
		idx = order.length;
	}
};

var ordering = function(order) {
	return function(a, b) {
		return getOutputOrder(order, a) - getOutputOrder(order, b);
	};
};

}


sdp
	= line:(line:SdpLine {return line;}) lines:(_eol line2:SdpLine {return line2;})* _eol*
	{
		lines.splice(0, 0, line);
		var sdp = aggregate(lines);
		return sdp;
	};

_eol = [\r\n]+

_ =[ \t]+;

eq = "=";

versionNumber
	= n: number { return n; };

number
	= n: ([\-0-9]+) { return guessType(text()); };

str
	= s: ([^ \t\n\r]+) { return text();}

SdpLine
	= version / origin / media / connection / timing / repeat / timezones / encryptionKey / bandwidth / attribute / otherType;

version
	= "v" eq v: versionNumber { return {version: v}; };

time
	= t: number { return options.useUnixTimes ? t - NTP_OFFSET : t;};

duration
	= x:number p:("d" / "h" / "m" / "s") { return x * utils.DURATIONS[p];}
	/ x:number { return x;};


origin
	= "o" eq
	username:str
	_ sessionId:str
	_ sessionVersion:versionNumber
	_ networkType:str
	_ addressType:str
	_ unicastAddress:str
	{
		var o = {
				username: username,
				sessionId: sessionId,
				sessionVersion: sessionVersion,
				networkType: networkType,
				addressType: addressType,
				unicastAddress: unicastAddress
		};
		var or = {};
		or[utils.SDP_TYPES["o"]] = o;
		return or;
	};

connection
	= "c" eq
	networkType:str
	_ addressType:str
	_ connectionAddress: str
	{
		return {connection: {
				networkType: networkType,
				addressType: addressType,
				connectionAddress: connectionAddress
		}};
	};

media
	= "m" eq type:str
	_ port:number
	numberOfPorts:("/" n:number {return n;}) ?
	_ protocol:([^ \t]+ {return text();})
	formats:(_ format:str { return format;})+
	{
		var m = {
			type: type
			, port: port
			, protocol: protocol
		};
		if (numberOfPorts) {
			m.numberOfPorts = numberOfPorts;
		}
		// TODO better detection of RTP
		if (options.parseRtpPayloads !== false && protocol.indexOf("RTP/") >= 0) {
			m.payloads = formats;
			m.payloads.forEach(function(value, index, arr) {
					arr[index] = guessType(value);
				});
		} else {
			m.formats = formats;
		}
		return {media: m};
	}

bandwidth
	= "b" eq type: str ":" value: str { return {bandwidth: {type: type, value: value}}};

timing
	= "t" eq start:time _ stop:time {return {timing:{start: start, stop: stop}}};

repeat
	= "r" eq interval:duration _ activeDuration:duration offsets:(_ d:duration {return d;})*
	{ return {repeat: {interval: interval, activeDuration: activeDuration, offsets: offsets}}};

timezones
	= "z" eq t:timezone ts:(_ t2:timezone {return t2;})+
	{ return {timezones: [t].concat(ts)};};

timezone
	= adjustment:number _ offset:duration {return {adjustment: adjustment, offset: offset}};

encryptionKey
	= "k" eq method:([^:\r\n]+ {return text();}) ":" key:str { return {encryptionKey: {method: method, key: key}};}
	/ "k" eq method:str { return {encryptionKey: {method: method}};};

attribute
	= rtpmapAttribute / fmtpAttribute / valueAttribute / propertyAttribute;

rtpmapAttribute
	= "a" eq "rtpmap" ":" payload:number
	_ codec:([^/]+ {return text();})
	"/" rate:number codecParams:("/" params:str {return guessType(params);})?
	{
		var rtp = {
				payload: payload,
				codec: codec,
				rate: rate
		};
		if (codecParams) {
			rtp.codecParams = codecParams;
		}
		return {rtp: rtp};
	};

fmtpAttribute
	= "a" eq "fmtp" ":" payload:number
	_ params:formatParameters
	{
		return { fmtp: {
				payload: payload,
				params: params
		}};
	};

formatParameters
	= param:formatParameter params:(";" [ \t]* p:formatParameter {return p;})*
	{
		if (params) {
			params.splice(0, 0, param);
		} else {
			params = [param];
		}
		return aggregateSdpProperties(params);
	}
	/ config:[^\r\n]+ { return text();};

formatParameter
	= name:([^=;\r\n]+ {return text()})
	eq value:([^;\r\n]+ {return guessType(text());})
	{ var param = {}; param[name] = value; return param;}

propertyAttribute
	= "a" eq property: attributeName
	{
		var p = {};
		p[property] = true;
		return p;
	}

valueAttribute
	= "a" eq property: attributeName ":" value:([^\n\r]+ {return guessType(text());})
	{
		var p = {};
		p[property] = value;
		return p;
	}

attributeName
	= ([^\n\r:]+)
	{
		var name = text();
		if (options["useLongNames"] !== false && utils.SDP_TYPES[name]) {
			return utils.SDP_TYPES[name];
		}
		return name;
	};

otherType
	= type: [a-z] eq value: ([^\r\n]+ {return text();})
	{
		var t = {};
		t[utils.SDP_TYPES[type] ? utils.SDP_TYPES[type] : type] = value;
		return t;
	};
