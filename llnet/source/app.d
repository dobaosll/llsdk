import core.thread;
import std.algorithm : remove;
import std.base64;
import std.bitmanip;
import std.conv;
import std.datetime.stopwatch;
import std.digest;
import std.functional;
import std.json;
import std.getopt;
import std.socket;
import std.stdio;
import std.string;

import connection;
import knxnet;
import redis_helper;
import llsdk;

// no more than 30 symbols
enum FRIENDLY_NAME = "dobaos_net";
enum TCONN_TIMEOUT = 6000.msecs;

void main(string[] args) {
	writeln("hello, friend");

	string prefix = "dobaosll";
  string addrCfg;
  string portCfg;

  RedisHelper redisAbs;
  try {
	  redisAbs = new RedisHelper();
  } catch(Exception e) {
    writeln("Exception while initializing redis client:");
    writeln(e.message);
    return;
  }
	void setUdpAddr(string opt, string value) {
		addrCfg = value;
		redisAbs.setKey(prefix ~ ":config:net:udp_addr", addrCfg);
	}
	void setUdpPort(string opt, string value) {
		portCfg = value;
		redisAbs.setKey(prefix ~ ":config:net:udp_port", portCfg);
	}

	auto getoptResult = getopt(args,
			"prefix|c", 
			"Prefix for redis config and stream keys. Default: dobaosll",
			&prefix,

			"bind|b",
			"IP address to bind UDP socket to. Default: 0.0.0.0", 
			&setUdpAddr,

			"port|p", 
			"UDP port. Default: 3671", 
			&setUdpPort);

	if (getoptResult.helpWanted) {
		defaultGetoptPrinter("SDK for Weinzierl BAOS 83x Data Link Layer.",
				getoptResult.options);
		return;
	}

	addrCfg = redisAbs.getKey(prefix ~ ":config:net:udp_addr", "0.0.0.0", true);
	portCfg = redisAbs.getKey(prefix ~ ":config:net:udp_port", "3671", true);
 
	auto port = to!ushort(portCfg);

	// UDP socket
	auto s = new UdpSocket();
	s.blocking(false);
	auto addr = new InternetAddress(addrCfg, port);
	s.bind(addr);

	writeln("UDP socket created");

	string macCfg = redisAbs.getKey(prefix ~ ":config:net:mac", "AAAAAAAA", true);
	auto mac = Base64.decode(macCfg);
	writefln("Mac address: ", mac.toHexString);

	// individual address for connections
	auto tunIaCfg = redisAbs.getKey(prefix ~ ":config:net:ia", "15.15.200", true);
	writeln("Reserved individual address: ", tunIaCfg);
	auto tunIa = str2ia(tunIaCfg);

	auto mprop = new MProp("127.0.0.1", 6379, prefix);
	auto mprop_readed = false;
	ubyte[] sn;
	ubyte subnetwork, deviceAddr;

	while(!mprop_readed) {
		try {
			// serial number of device
			sn = mprop.read(11);
			// read baos address
			subnetwork = mprop.read(57)[0];
			deviceAddr = mprop.read(58)[0];
			mprop_readed = true;
		} catch(Exception e) {
			writeln("Error reading MPROP: ", e.message);
			writeln("Retrying..");
		}
	}
	writefln("Serial number: %s", sn.toHexString);
	ushort realIa = to!ushort(subnetwork << 8 | deviceAddr);
	string realIaStr = ia2str(realIa);
	writeln("BAOS module individual address: ", realIaStr);

	auto maxConnCntCfg = redisAbs.getKey(prefix ~ ":config:net:conn_count", "10", true);
	auto maxConnCnt = to!int(maxConnCntCfg);

	LLClient dobaosll = new LLClient("127.0.0.1", 6379, prefix);

	//  ========================================= \\
	// ============================================ \\

	KnxNetConnection[] connections;
	connections.length = maxConnCnt;

	void queue2socket(int ci) {
		// process queue. send next frames if ack received
		auto data = connections[ci].processQueue();
		if (data.length > 0) {
			connections[ci].ackReceived = false;
			connections[ci].sentReqCount += 1;
			connections[ci].lastReq = data;
			writeln("to client >>>: ",
					data.toHexString, " to: ",  connections[ci].addr);
			s.sendTo(data, connections[ci].addr);
			connections[ci].swAck.reset();
			connections[ci].swAck.start();
		}
	}

	for (int i = 0; i < connections.length; i += 1) {
		connections[i].ia = tunIa;
	}

	// available channel
	int findAvailableChannel() {
		int result = 0xff;
		for (int i = 0; i < connections.length; i += 1) {
			// if cell in array is not initialized
			if (!connections[i].active) {
				result = to!ubyte(i);
				break;
			}
		}

		return result;
	}

	void parseKnxNetMessage(ubyte[] message, Address from) {
		// example: [06 10 02 06 00 08] [00 24]
		// first, parse header
		try {
			auto headerLen = message.read!ubyte();
			if (headerLen != KNXConstants.SIZE_10) {
				writeln("wrong header length");
				return;
			}
			auto headerVer = message.read!ubyte();
			if (headerVer != KNXConstants.VERSION_10) {
				writeln("wrong version");
				// TODO: E_VERSION_NOT_SUPPORTED
				return;
			}
			auto knxService = message.read!ushort();
			auto totalLen = message.read!ushort();
			switch(knxService) {
				case KNXServices.CONNECT_REQUEST:
					writeln("ConnectRequest: ", message.toHexString);
					auto hpai1len = message.read!ubyte();
					auto hpai1 = message[0..hpai1len-1];
					message = message[hpai1len-1..$];
					auto hpai2len = message.read!ubyte();
					auto hpai2 = message[0..hpai2len-1];
					message = message[hpai1len-1..$];
					auto criLen = message.read!ubyte();
					auto cri = message[0..criLen-1];
					// 4 2 0, for example
					// 4 - TUNNEL_CONNECTION
					// 2 - CRI.TUNNEL_LINK_LAYER
					// 0 - reserved
					auto connType = cri[0];

					if (connType != KNXConnTypes.TUNNEL_CONNECTION && 
							connType != KNXConnTypes.DEVICE_MGMT_CONNECTION ) {
						// send error
						auto responseFrame = connectResponseError(0x00, KNXErrorCodes.E_CONNECTION_TYPE);
						writeln("ConnectResponseError: ", responseFrame.toHexString);
						sendKNXIPMessage(KNXServices.CONNECT_RESPONSE, responseFrame, s, from);
						return;
					} 
					if (connType == KNXConnTypes.TUNNEL_CONNECTION) { 
						auto knxLayer = cri[1];
						if(knxLayer != CRI.TUNNEL_LINKLAYER) {
							// check if CRI.TUNNEL_LINK_LAYER
							// go next. otherwise - ERROR unsupported E_TUNNEL_LAYER 0x29
							// send error 0x29
							auto responseFrame = connectResponseError(0x00, KNXErrorCodes.E_TUNNELING_LAYER);
							writeln("ConnectResponseError: ", responseFrame.toHexString);
							sendKNXIPMessage(KNXServices.CONNECT_RESPONSE, responseFrame, s, from);
							return;
						}
					}

					// find first available cell in array
					auto chIndex = findAvailableChannel();
					if (chIndex == 0xff) {
						auto responseFrame = connectResponseError(0x00, KNXErrorCodes.E_NO_MORE_CONNECTIONS);
						writeln("ConnectResponseError: ", responseFrame.toHexString);
						sendKNXIPMessage(KNXServices.CONNECT_RESPONSE, responseFrame, s, from);
						return;
					}
					// put connection into array
					auto chNumber = to!ubyte(chIndex + 1);
					connections[chIndex].active = true;
					connections[chIndex].addr = from;
					connections[chIndex].channel = chNumber;
					connections[chIndex].sequence = 0x00;
					connections[chIndex].outSequence = 0x00;
					connections[chIndex].type = connType;
					connections[chIndex].ackReceived = true;
					connections[chIndex].queue = [];
					connections[chIndex].swCon.reset();
					connections[chIndex].swCon.start();
					connections[chIndex].swAck.reset();
					connections[chIndex].lastCemiToBaos = [];
					connections[chIndex].tconns.clear();
					ushort ia = connections[chIndex].ia;
					// send response indicating success
					auto responseFrame = connectResponseSuccess(chNumber, connType, ia);
					writeln("ConnectResponseSuccess: ", responseFrame.toHexString);
					sendKNXIPMessage(KNXServices.CONNECT_RESPONSE, responseFrame, s, from);
					break;
				case KNXServices.CONNECTIONSTATE_REQUEST:
					auto chId = message.read!ubyte();
					auto reserved = message.read!ubyte();
					auto hpaiLen = message.read!ubyte();
					auto hpai = message[0..hpaiLen-1];
					message = message[hpaiLen-1..$];

					// channel value in knx is (<index in array> + 1)
					// therefore,
					bool found = connections[chId - 1].channel == chId;
					bool active = connections[chId - 1].active;

					// generate response
					if (found && active) {
						auto stateFrame = connectionStateResponse(KNXErrorCodes.E_NO_ERROR, chId);
						writeln("ConnStateResponseSuccess: ", stateFrame.toHexString);
						sendKNXIPMessage(KNXServices.CONNECTIONSTATE_RESPONSE, stateFrame, s, from);
						// restart timeout watch 
						connections[chId - 1].swCon.reset();
						connections[chId - 1].swCon.start();
					} else {
						auto stateFrame = connectionStateResponse(KNXErrorCodes.E_CONNECTION_ID, chId);
						writeln("ConnStateResponseError: ", stateFrame.toHexString);
						sendKNXIPMessage(KNXServices.CONNECTIONSTATE_RESPONSE, stateFrame, s, from);
					}
					break;
				case KNXServices.DISCONNECT_RESPONSE:
					writeln("DisconnectResponse: ", message.toHexString);
					auto chId = message.read!ubyte();
					bool found = connections[to!int(chId) - 1].channel == chId;
					bool active = connections[to!int(chId) - 1].active;
					int chIndex = -1;
					if (found) {
						chIndex = to!int(chId) - 1;
						connections[chIndex].active = false;
						connections[chIndex].channel = 0x00;
						connections[chIndex].sequence = 0x00;
						connections[chIndex].outSequence = 0x00;
						connections[chIndex].swCon.stop();
						connections[chIndex].swAck.stop();
					}
					break;
				case KNXServices.DISCONNECT_REQUEST:
					auto chId = message.read!ubyte();
					auto reserved = message.read!ubyte();
					auto hpaiLen = message.read!ubyte();
					auto hpai = message[0..hpaiLen-1];
					message = message[hpaiLen-1..$];

					// channel value in knx is (<index in array> + 1)
					// therefore,
					bool found = connections[to!int(chId) - 1].channel == chId;
					bool active = connections[to!int(chId) - 1].active;
					int chIndex = -1;
					if (found) {
						chIndex = to!int(chId) - 1;
						// disconnect and send response
						connections[chIndex].active = false;
						connections[chIndex].channel = 0x00;
						connections[chIndex].sequence = 0x00;
						connections[chIndex].outSequence = 0x00;
						connections[chIndex].swCon.stop();
						connections[chIndex].swAck.stop();

						auto disconnectFrame = disconnectResponse(KNXErrorCodes.E_NO_ERROR, chId);
						writeln("DisconnectResponse success: ", disconnectFrame.toHexString);
						sendKNXIPMessage(KNXServices.DISCONNECT_RESPONSE, disconnectFrame, s, from);
					} else {
						auto disconnectFrame = disconnectResponse(KNXErrorCodes.E_CONNECTION_ID, chId);
						writeln("DisconnectResponse error: ", disconnectFrame.toHexString);
						sendKNXIPMessage(KNXServices.DISCONNECT_RESPONSE, disconnectFrame, s, from);
					}
					break;
				case KNXServices.DESCRIPTION_REQUEST:
					auto descrFrame = descriptionResponse(tunIa, sn, mac, FRIENDLY_NAME);
					sendKNXIPMessage(KNXServices.DESCRIPTION_RESPONSE, descrFrame, s, from);
					break;
				case KNXServices.DEVICE_CONFIGURATION_ACK:
				case KNXServices.TUNNELING_ACK:
					// basically, the same. services should differ
					auto structLen = message.read!ubyte();
					auto chId = message.read!ubyte();
					// channel value in knx is (<index in array> + 1)
					// therefore,
					bool found = connections[chId - 1].channel == chId;
					bool active = connections[chId - 1].active;

					if (!found || !active) {
						// if connection is not in array or not active
						// client will resend request few times after timeout
						// then should reconnect
						return;
					}
					auto chIndex = to!int(chId) - 1;

					// 3. parse next
					// seq, 
					auto seqId = message.read!ubyte();
					auto ackSeqId = to!int(seqId);
					auto expSeqId = to!int(connections[chIndex].outSequence);
					writeln("Incoming ACK sequence id: ", ackSeqId, ", expected: ", expSeqId);
					if (ackSeqId == expSeqId) {
						connections[chIndex].increaseOutSeqId();
						connections[chIndex].ackReceived = true;
						connections[chIndex].sentReqCount = 0;
						//connections[chIndex].processQueue();
						queue2socket(chIndex);
					}
					break;
				case KNXServices.TUNNELING_REQUEST:
				case KNXServices.DEVICE_CONFIGURATION_REQUEST:
					auto resService = KNXServices.TUNNELING_ACK;
					// basically, the same. services should differ
					if (knxService == KNXServices.DEVICE_CONFIGURATION_REQUEST) {
						resService = KNXServices.DEVICE_CONFIGURATION_ACK;
					} else {
						// tunneling req
					}
					// 0. start parsing
					auto structLen = message.read!ubyte();
					auto chId = message.read!ubyte();

					// channel value in knx is (<index in array> + 1)
					// therefore,
					bool found = connections[chId - 1].channel == chId;
					bool active = connections[chId - 1].active;

					if (!found || !active) {
						// if connection is not in array or not active
						// client will resend request few times after timeout
						// then should reconnect
						return;
					}
					auto chIndex = to!int(chId) - 1;

					// 3. parse next
					// seq, 
					auto seqId = message.read!ubyte();

					// sequence id checkings *** debug needed
					auto clientSeqId = to!int(seqId);
					auto expectSeqId = to!int(connections[chIndex].sequence);
					writeln("Tunneling req seq id: ", clientSeqId, ", expected: ", expectSeqId);
					if (clientSeqId == expectSeqId) {
						// expected - good. ACK, process frame

						// reserved, cemi frame
						auto reserved = message.read!ubyte();
						auto cemiFrame = message[0..$];

						auto offset = 0;
						ubyte mc = cemiFrame.peek!ubyte(offset); offset += 1;
						bool sendToBaos = true;
						LData_cEMI decoded;
						if (mc == MC.LDATA_REQ || 
								mc == MC.LDATA_CON || mc == MC.LDATA_IND) {
							decoded = new LData_cEMI(cemiFrame);
							if (!decoded.address_type_group &&
									(decoded.tservice == TService.TConnect ||
									 decoded.tservice == TService.TDataConnected ||
									 decoded.tservice == TService.TAck || 
									 decoded.tservice == TService.TNack || 
									 decoded.tservice == TService.TDisconnect)) {
								ushort dest = decoded.dest;
								// for connection-oriented data check at first if
								// transport connection was established for this client
								bool somebodyElseConnected = false;
								for(int i = 0; i < connections.length; i += 1) {
									if ((dest in connections[i].tconns) is null) {
										continue;
									}
									somebodyElseConnected = (i != chIndex);
									// if request come from right client, reset timer
									if (i == chIndex) {
										connections[i].tconns[dest].reset();
									}
								}
								if (somebodyElseConnected) {
									// acknowledge receiving request, send back to client
									auto ackFrame = ack(chId, seqId);
									sendKNXIPMessage(resService, ackFrame, s, from);
									// send LDataCon with error back to client
									decoded.message_code = MC.LDATA_CON;
									decoded.source = tunIa;
									decoded.error = true;
									connections[chIndex].add2queue(
											KNXServices.TUNNELING_REQUEST, decoded.toUbytes());
									queue2socket(chIndex);
									// erase info about last sent cemi data
									connections[chIndex].lastCemiToBaos = [];
									// increase sequence number of connection
									connections[chIndex].increaseSeqId();
									// reset timeout stopwatch
									connections[chIndex].swCon.reset();
									connections[chIndex].swCon.start();
									break;
								}
							}
						}

						// acknowledge receiving request, send back to client
						auto ackFrame = ack(chId, seqId);
						sendKNXIPMessage(resService, ackFrame, s, from);

						writeln("-------------------------------");
						writeln("Sending to BAOS: ", cemiFrame.toHexString);
						if (mc == MC.LDATA_REQ || mc == MC.LDATA_CON || mc == MC.LDATA_IND) {
							string destStr = decoded.address_type_group?
								grp2str(decoded.dest): ia2str(decoded.dest);
						}
						// send cemi to BAOS module
						dobaosll.sendCemi(cemiFrame);
						// store last sent frame
						connections[chIndex].lastCemiToBaos = cemiFrame.dup;

						// increase sequence number of connection
						connections[chIndex].increaseSeqId();
						// reset timeout stopwatch
						connections[chIndex].swCon.reset();
						connections[chIndex].swCon.start();
						writeln("-------------------------------");
					} else if (clientSeqId == expectSeqId - 1) {
						// ACK, discard frame
						// acknowledge receiving request, send back to client
						auto ackFrame = ack(chId, seqId);
						writeln("Sending tunneling ack: ", ackFrame.toHexString);
						sendKNXIPMessage(resService, ackFrame, s, from);
					} else {
						// discard
						writeln("Sequence id not expected, not one less");
					}
					break;
				default:
					writeln("Unsupported service");
					break;
			}
		} catch(Exception e) {
			writeln("Exeption processing UDP message", e);
		} catch(Error e) {
			writeln("Error processing UDP message", e);
		}
	}

	void onCemiFrame(ubyte[] cemi) {
		writeln("<<< from BAOS: ", cemi.toHexString);
		// Device management should support:
		// client => server
		//   M_PropRead.req
		//   M_PropWrite.req
		//   M_Reset.req
		//   M_FuncPropCommand.req
		//   M_FuncPropStateRead.req
		//   cEMI T_Data_Individual.req - dev management v2
		//   cEMI T_Data_Connected.req - dev management v2

		// In this procedure matters server => client
		//   M_PropRead.con
		//   M_PropWrite.con
		//   M_PropInfo.ind
		//   M_FuncPropStateResponse.con
		//   cEMI T_Data_Individual.ind - v2
		//   cEMI T_Data_Connected.ind - v2
		// 
		//   MPROPREAD_REQ = 0xFC,
		//   MPROPREAD_CON = 0xFB,
		//   MPROPWRITE_REQ = 0xF6,
		//   MPROPWRITE_CON = 0xF5,
		//   MPROPINFO_IND = 0xF7,
		//   MRESET_REQ = 0xF1,
		//   MRESET_IND = 0xF0

		// tunneling
		//  LDATA_REQ = 0x11,
		//  LDATA_CON = 0x2E,
		//  LDATA_IND = 0x29,

		int offset = 0;
		ubyte mc = cemi.peek!ubyte(offset); offset += 1;
		LData_cEMI parsed;
		if (mc == MC.LDATA_CON || mc == MC.LDATA_IND) {
			parsed = new LData_cEMI(cemi);
			string destStr = parsed.address_type_group? 
				grp2str(parsed.dest): ia2str(parsed.dest);
		} else if (mc == MC.MPROPREAD_CON) {
			writeln("MPropRead.Con frame");
		} else if (mc == MC.MPROPWRITE_CON) {
			writeln("MPropWrite.Con frame");
		} else if (mc == MC.MPROPINFO_IND) {
			writeln("MPropInfo.Ind frame");
		} else if (mc == MC.MRESET_IND) {
			writeln("MReset.Ind frame");
			mprop_readed = false;
			while(!mprop_readed) {
				try {
					// serial number of device
					sn = mprop.read(11);
					subnetwork = mprop.read(57)[0];
					deviceAddr = mprop.read(58)[0];
					mprop_readed = true;
				} catch(Exception e) {
					writeln("Error reading MPROP: ", e.message);
					writeln("Retrying..");
				}
			}
			writefln("Serial number: %s", sn.toHexString);
			realIa = to!ushort(subnetwork << 8 | deviceAddr);
			realIaStr = ia2str(realIa);
			writeln("BAOS module individual address: ", realIaStr);
		} else {
			writeln("Unknown message code");
		}
		for (int i = 0; i < connections.length; i += 1) {
			auto conn = connections[i];
			if (!conn.active) {
				continue;
			}

			if (mc == MC.LDATA_CON &&
					conn.type == KNXConnTypes.TUNNEL_CONNECTION) {
				if (connections[i].lastCemiToBaos.length == 0) continue;
				LData_cEMI last = new LData_cEMI(connections[i].lastCemiToBaos);
				if (last.dest == parsed.dest &&
						last.tservice == parsed.tservice &&
						last.tseq == parsed.tseq &&
						last.apci == parsed.apci &&
						last.tiny_data == parsed.tiny_data &&
						last.data == parsed.data) {
					// "patch" addresses
					if (parsed.source == realIa) {
						parsed.source = connections[i].ia;
					}
					// connection is pending LData.con message, send
					connections[i].add2queue(KNXServices.TUNNELING_REQUEST, parsed.toUbytes());
					queue2socket(i);
					// if message was LDataCon for TConnect service
					// without confirmation error, then establish connection
					if (parsed.tservice == TService.TConnect &&
							!parsed.error) {
						connections[i].tconns[parsed.dest] = StopWatch(AutoStart.yes);
					}
					if (parsed.tservice == TService.TDisconnect &&
							!parsed.error) {
						connections[i].tconns.remove(parsed.dest);
					}
				} else if (parsed.address_type_group) {
					// connection is not pending LData.con message
					// change it to LData.ind and send
					// BUT only if addressType indicating group address (== 0b1);
					parsed.message_code = MC.LDATA_IND;
					// "patch" addresses
					if (parsed.source == realIa) {
						parsed.source = connections[i].ia;
					}
					connections[i].add2queue(KNXServices.TUNNELING_REQUEST, parsed.toUbytes());
					queue2socket(i);
					// return to LDATA_CON, so, next conn[i] iterations will check correctly
					parsed.message_code = MC.LDATA_CON;
					// erase info about last sent cemi data
					connections[i].lastCemiToBaos = [];
				}
			} else if (mc == MC.MPROPREAD_CON &&
					conn.type == KNXConnTypes.DEVICE_MGMT_CONNECTION)  {
				connections[i].add2queue(KNXServices.DEVICE_CONFIGURATION_REQUEST , cemi);
				queue2socket(i);
				connections[i].lastCemiToBaos = [];
			} else if (mc == MC.MPROPWRITE_CON
					&& conn.type == KNXConnTypes.DEVICE_MGMT_CONNECTION)  {
				connections[i].add2queue(KNXServices.DEVICE_CONFIGURATION_REQUEST , cemi);
				queue2socket(i);
			} else {
				//send unchanges to all connections
				if (mc == MC.LDATA_IND 
						&& conn.type == KNXConnTypes.TUNNEL_CONNECTION) {
					if (parsed.address_type_group) {
						connections[i].add2queue(KNXServices.TUNNELING_REQUEST , cemi);
						queue2socket(i);
					} else {
						// "patch" individual address
						if (parsed.dest == realIa) {
							parsed.dest = connections[i].ia;
						}

						if (parsed.tservice == TService.TDisconnect || 
								parsed.tservice == TService.TAck ||
								parsed.tservice == TService.TNack ||
								parsed.tservice == TService.TDataConnected) {
							if ((parsed.source in connections[i].tconns) !is null) {
								connections[i].add2queue(KNXServices.TUNNELING_REQUEST , cemi);
								queue2socket(i);
								connections[i].tconns[parsed.source].reset();
								if (parsed.tservice == TService.TDisconnect) {
									connections[i].tconns.remove(parsed.source);
								}
							}
						}
					}
				} else if (mc == MC.MPROPINFO_IND 
						&& conn.type == KNXConnTypes.DEVICE_MGMT_CONNECTION)  {
					connections[i].add2queue(KNXServices.DEVICE_CONFIGURATION_REQUEST , cemi);
					queue2socket(i);
				}
			}
		}
	}
	dobaosll.onCemi(toDelegate(&onCemiFrame));
	while(true) {
		char[1024] buf;
		Address from;
		auto recLen = s.receiveFrom(buf[], from);
		if (recLen > 0) {
			//writeln(cast(ubyte[])buf[0..recLen], from);
			parseKnxNetMessage(cast(ubyte[])buf[0..recLen], from);
		}
		dobaosll.processMessages();
		// check connections for timeout
		for (int i = 0; i < connections.length; i += 1) {
			auto conn = connections[i];
			if (conn.active) {
				queue2socket(i);
				// also check for ack timeouts
				auto conDur = conn.swCon.peek();
				auto ackDur = conn.swAck.peek();
				auto ackTimeout = ackDur > msecs(1*1000);

				// general timeout. if no any message from client, close connection
				// for test purpose - 1minute
				auto timeout = conDur > msecs(120*1000);
				if (timeout) {
					writeln("Connection TIMEOUT: ", conn.addr);			
					connections[i].swCon.stop();
					connections[i].swCon.reset();
					// send DISCONNECT_REQUEST
					// hpai: udp(1byte), ip(4byte), port(2byte)
					ubyte[] hpai = [1, 0, 0, 0, 0, 0, 0]; 
					auto discFrame = disconnectRequest(conn.channel, hpai);
					sendKNXIPMessage(KNXServices.DISCONNECT_REQUEST , discFrame, s, conn.addr);

					// in any case 
					connections[i].active = false;
				}
				// ack timeout - if no ACK from net client for server's TUNNEL_REQ
				if (!conn.ackReceived && ackTimeout) {
					writeln("Ack not received and timeout");
					if (conn.sentReqCount == 1) {
						writeln("Sending request one more time");
						writeln("Sending: ", conn.lastReq.toHexString," to:: ", conn.addr);
						// send again last frame
						s.sendTo(conn.lastReq, conn.addr);
						connections[i].sentReqCount += 1;
						// reset timeout watcher
						connections[i].swAck.reset();
					} else if (conn.sentReqCount > 1) {
						writeln("Disconnecting: ", conn.addr);
						// disconnect
						// send request at first
						ubyte[] hpai = [1, 0, 0, 0, 0, 0, 0]; 
						auto discFrame = disconnectRequest(conn.channel, hpai);
						sendKNXIPMessage(KNXServices.DISCONNECT_REQUEST , discFrame, s, conn.addr);
						// and make connection inactive
						connections[i].active = false;
						connections[i].lastReq = [];

						// stop timeout watchers
						connections[i].swCon.stop();
						connections[i].swAck.stop();
					}
				}
				// process transport connection timeouts
				foreach(dest, sw; conn.tconns) {
					timeout = conn.tconns[dest].peek() > TCONN_TIMEOUT;
					if (timeout) {
						sw.stop();
						connections[i].tconns.remove(dest);
					}
				}
			}
		}
		Thread.sleep(1.msecs);
	}
}
