{
	"patcher": {
		"fileversion": 1,
		"appversion": {
			"major": 8,
			"minor": 6,
			"revision": 0,
			"architecture": "x64",
			"modernui": 1
		},
		"classnamespace": "box",
		"rect": [
			100.0,
			100.0,
			820.0,
			820.0
		],
		"bglocked": 0,
		"openinpresentation": 0,
		"default_fontsize": 12.0,
		"default_fontface": 0,
		"default_fontname": "Arial",
		"gridonopen": 1,
		"gridsize": [
			15.0,
			15.0
		],
		"gridsnaponopen": 1,
		"objectsnaponopen": 1,
		"statusbarvisible": 2,
		"toolbarvisible": 1,
		"lefttoolbarpinned": 0,
		"toptoolbarpinned": 0,
		"righttoolbarpinned": 0,
		"bottomtoolbarpinned": 0,
		"toolbars_unpinned_last_save": 0,
		"tallnewobj": 0,
		"boxanimatetime": 200,
		"enablehscroll": 1,
		"enablevscroll": 1,
		"devicewidth": 0.0,
		"description": "",
		"digest": "",
		"tags": "",
		"style": "",
		"subpatcher_template": "",
		"assistshowspatchername": 0,
		"boxes": [
			{
				"box": {
					"id": "obj-1",
					"maxclass": "comment",
					"numinlets": 1,
					"numoutlets": 0,
					"patching_rect": [
						30.0,
						15.0,
						720.0,
						33.0
					],
					"text": "TrackOSC receiver for Max \u2014 needs trackosc.parse.js next to this patch. Send from an iPhone/Mac TrackOSC sender to this machine, port 9527."
				}
			},
			{
				"box": {
					"id": "obj-2",
					"maxclass": "newobj",
					"numinlets": 1,
					"numoutlets": 1,
					"patching_rect": [
						30.0,
						60.0,
						272.0,
						22.0
					],
					"text": "udpreceive 9527 @maxpacketsize 65536",
					"outlettype": [
						""
					]
				}
			},
			{
				"box": {
					"id": "obj-3",
					"maxclass": "newobj",
					"numinlets": 1,
					"numoutlets": 4,
					"patching_rect": [
						30.0,
						100.0,
						160.0,
						22.0
					],
					"text": "js trackosc.parse.js",
					"outlettype": [
						"",
						"",
						"",
						""
					],
					"saved_object_attributes": {
						"filename": "trackosc.parse.js",
						"parameter_enable": 0
					}
				}
			},
			{
				"box": {
					"id": "obj-4",
					"maxclass": "newobj",
					"numinlets": 1,
					"numoutlets": 1,
					"patching_rect": [
						400.0,
						60.0,
						76.0,
						22.0
					],
					"text": "loadbang",
					"outlettype": [
						"bang"
					]
				}
			},
			{
				"box": {
					"id": "obj-5",
					"maxclass": "toggle",
					"numinlets": 1,
					"numoutlets": 1,
					"patching_rect": [
						400.0,
						100.0,
						24.0,
						24.0
					],
					"outlettype": [
						"int"
					]
				}
			},
			{
				"box": {
					"id": "obj-6",
					"maxclass": "newobj",
					"numinlets": 2,
					"numoutlets": 1,
					"patching_rect": [
						400.0,
						140.0,
						76.0,
						22.0
					],
					"text": "metro 33",
					"outlettype": [
						"bang"
					]
				}
			},
			{
				"box": {
					"id": "obj-7",
					"maxclass": "newobj",
					"numinlets": 1,
					"numoutlets": 1,
					"patching_rect": [
						400.0,
						260.0,
						174.0,
						22.0
					],
					"text": "jit.lcd 4 char 720 960",
					"outlettype": [
						"jit_matrix"
					]
				}
			},
			{
				"box": {
					"id": "obj-8",
					"maxclass": "jit.pwindow",
					"numinlets": 1,
					"numoutlets": 2,
					"patching_rect": [
						400.0,
						300.0,
						360.0,
						480.0
					],
					"outlettype": [
						"",
						""
					]
				}
			},
			{
				"box": {
					"id": "obj-9",
					"maxclass": "comment",
					"numinlets": 1,
					"numoutlets": 0,
					"patching_rect": [
						440.0,
						143.0,
						320.0,
						20.0
					],
					"text": "drawing: [js] emits jit.lcd commands on each bang"
				}
			},
			{
				"box": {
					"id": "obj-10",
					"maxclass": "newobj",
					"numinlets": 1,
					"numoutlets": 1,
					"patching_rect": [
						30.0,
						150.0,
						132.0,
						22.0
					],
					"text": "print camerainfo",
					"outlettype": [
						""
					]
				}
			},
			{
				"box": {
					"id": "obj-11",
					"maxclass": "comment",
					"numinlets": 1,
					"numoutlets": 0,
					"patching_rect": [
						30.0,
						200.0,
						360.0,
						33.0
					],
					"text": "outlet 1: <kind> <det> <joint> xNorm yNorm c \u2014 route the first body's nose and left wrist"
				}
			},
			{
				"box": {
					"id": "obj-12",
					"maxclass": "newobj",
					"numinlets": 1,
					"numoutlets": 2,
					"patching_rect": [
						30.0,
						240.0,
						90.0,
						22.0
					],
					"text": "route pose",
					"outlettype": [
						"",
						""
					]
				}
			},
			{
				"box": {
					"id": "obj-13",
					"maxclass": "newobj",
					"numinlets": 1,
					"numoutlets": 2,
					"patching_rect": [
						30.0,
						280.0,
						69.0,
						22.0
					],
					"text": "route 0",
					"outlettype": [
						"",
						""
					]
				}
			},
			{
				"box": {
					"id": "obj-14",
					"maxclass": "newobj",
					"numinlets": 1,
					"numoutlets": 3,
					"patching_rect": [
						30.0,
						320.0,
						160.0,
						22.0
					],
					"text": "route nose leftWrist",
					"outlettype": [
						"",
						"",
						""
					]
				}
			},
			{
				"box": {
					"id": "obj-15",
					"maxclass": "newobj",
					"numinlets": 1,
					"numoutlets": 3,
					"patching_rect": [
						30.0,
						360.0,
						104.0,
						22.0
					],
					"text": "unpack f f f",
					"outlettype": [
						"float",
						"float",
						"float"
					]
				}
			},
			{
				"box": {
					"id": "obj-16",
					"maxclass": "newobj",
					"numinlets": 1,
					"numoutlets": 1,
					"patching_rect": [
						30.0,
						400.0,
						153.0,
						22.0
					],
					"text": "scale 0. 1. 48. 84.",
					"outlettype": [
						""
					]
				}
			},
			{
				"box": {
					"id": "obj-17",
					"maxclass": "newobj",
					"numinlets": 1,
					"numoutlets": 1,
					"patching_rect": [
						30.0,
						440.0,
						48.0,
						22.0
					],
					"text": "mtof",
					"outlettype": [
						""
					]
				}
			},
			{
				"box": {
					"id": "obj-18",
					"maxclass": "newobj",
					"numinlets": 2,
					"numoutlets": 2,
					"patching_rect": [
						30.0,
						480.0,
						76.0,
						22.0
					],
					"text": "line~ 20",
					"outlettype": [
						"signal",
						"bang"
					]
				}
			},
			{
				"box": {
					"id": "obj-19",
					"maxclass": "newobj",
					"numinlets": 2,
					"numoutlets": 1,
					"patching_rect": [
						30.0,
						520.0,
						62.0,
						22.0
					],
					"text": "cycle~",
					"outlettype": [
						"signal"
					]
				}
			},
			{
				"box": {
					"id": "obj-20",
					"maxclass": "newobj",
					"numinlets": 1,
					"numoutlets": 1,
					"patching_rect": [
						160.0,
						400.0,
						146.0,
						22.0
					],
					"text": "scale 0. 1. 0.5 0.",
					"outlettype": [
						""
					]
				}
			},
			{
				"box": {
					"id": "obj-21",
					"maxclass": "newobj",
					"numinlets": 2,
					"numoutlets": 2,
					"patching_rect": [
						160.0,
						440.0,
						76.0,
						22.0
					],
					"text": "line~ 20",
					"outlettype": [
						"signal",
						"bang"
					]
				}
			},
			{
				"box": {
					"id": "obj-22",
					"maxclass": "newobj",
					"numinlets": 2,
					"numoutlets": 1,
					"patching_rect": [
						30.0,
						560.0,
						40.0,
						22.0
					],
					"text": "*~",
					"outlettype": [
						"signal"
					]
				}
			},
			{
				"box": {
					"id": "obj-23",
					"maxclass": "newobj",
					"numinlets": 1,
					"numoutlets": 3,
					"patching_rect": [
						230.0,
						360.0,
						104.0,
						22.0
					],
					"text": "unpack f f f",
					"outlettype": [
						"float",
						"float",
						"float"
					]
				}
			},
			{
				"box": {
					"id": "obj-24",
					"maxclass": "newobj",
					"numinlets": 1,
					"numoutlets": 1,
					"patching_rect": [
						230.0,
						400.0,
						174.0,
						22.0
					],
					"text": "scale 0. 1. 4000. 200.",
					"outlettype": [
						""
					]
				}
			},
			{
				"box": {
					"id": "obj-25",
					"maxclass": "newobj",
					"numinlets": 1,
					"numoutlets": 1,
					"patching_rect": [
						230.0,
						440.0,
						62.0,
						22.0
					],
					"text": "noise~",
					"outlettype": [
						"signal"
					]
				}
			},
			{
				"box": {
					"id": "obj-26",
					"maxclass": "newobj",
					"numinlets": 3,
					"numoutlets": 1,
					"patching_rect": [
						230.0,
						480.0,
						125.0,
						22.0
					],
					"text": "lores~ 800. 0.5",
					"outlettype": [
						"signal"
					]
				}
			},
			{
				"box": {
					"id": "obj-27",
					"maxclass": "newobj",
					"numinlets": 2,
					"numoutlets": 1,
					"patching_rect": [
						230.0,
						520.0,
						69.0,
						22.0
					],
					"text": "*~ 0.15",
					"outlettype": [
						"signal"
					]
				}
			},
			{
				"box": {
					"id": "obj-28",
					"maxclass": "gain~",
					"numinlets": 2,
					"numoutlets": 2,
					"patching_rect": [
						30.0,
						600.0,
						24.0,
						100.0
					],
					"outlettype": [
						"signal",
						"int"
					]
				}
			},
			{
				"box": {
					"id": "obj-29",
					"maxclass": "ezdac~",
					"numinlets": 2,
					"numoutlets": 0,
					"patching_rect": [
						30.0,
						720.0,
						45.0,
						45.0
					]
				}
			},
			{
				"box": {
					"id": "obj-30",
					"maxclass": "comment",
					"numinlets": 1,
					"numoutlets": 0,
					"patching_rect": [
						100.0,
						610.0,
						280.0,
						47.0
					],
					"text": "nose x \u2192 pitch, nose y \u2192 loudness; left wrist height \u2192 noise filter. Turn on audio (ezdac~) and raise the gain."
				}
			},
			{
				"box": {
					"id": "obj-31",
					"maxclass": "newobj",
					"numinlets": 1,
					"numoutlets": 1,
					"patching_rect": [
						400.0,
						200.0,
						97.0,
						22.0
					],
					"text": "print boxes",
					"outlettype": [
						""
					]
				}
			},
			{
				"box": {
					"id": "obj-32",
					"maxclass": "comment",
					"numinlets": 1,
					"numoutlets": 0,
					"patching_rect": [
						480.0,
						200.0,
						300.0,
						33.0
					],
					"text": "outlet 2: <kind> <det> l t w h <label\u2026> (normalised) \u2014 text, animal, human, facebox, barcode"
				}
			}
		],
		"lines": [
			{
				"patchline": {
					"source": [
						"obj-2",
						0
					],
					"destination": [
						"obj-3",
						0
					]
				}
			},
			{
				"patchline": {
					"source": [
						"obj-4",
						0
					],
					"destination": [
						"obj-5",
						0
					]
				}
			},
			{
				"patchline": {
					"source": [
						"obj-5",
						0
					],
					"destination": [
						"obj-6",
						0
					]
				}
			},
			{
				"patchline": {
					"source": [
						"obj-6",
						0
					],
					"destination": [
						"obj-3",
						0
					]
				}
			},
			{
				"patchline": {
					"source": [
						"obj-3",
						3
					],
					"destination": [
						"obj-7",
						0
					]
				}
			},
			{
				"patchline": {
					"source": [
						"obj-7",
						0
					],
					"destination": [
						"obj-8",
						0
					]
				}
			},
			{
				"patchline": {
					"source": [
						"obj-3",
						0
					],
					"destination": [
						"obj-10",
						0
					]
				}
			},
			{
				"patchline": {
					"source": [
						"obj-3",
						1
					],
					"destination": [
						"obj-12",
						0
					]
				}
			},
			{
				"patchline": {
					"source": [
						"obj-12",
						0
					],
					"destination": [
						"obj-13",
						0
					]
				}
			},
			{
				"patchline": {
					"source": [
						"obj-13",
						0
					],
					"destination": [
						"obj-14",
						0
					]
				}
			},
			{
				"patchline": {
					"source": [
						"obj-14",
						0
					],
					"destination": [
						"obj-15",
						0
					]
				}
			},
			{
				"patchline": {
					"source": [
						"obj-15",
						0
					],
					"destination": [
						"obj-16",
						0
					]
				}
			},
			{
				"patchline": {
					"source": [
						"obj-16",
						0
					],
					"destination": [
						"obj-17",
						0
					]
				}
			},
			{
				"patchline": {
					"source": [
						"obj-17",
						0
					],
					"destination": [
						"obj-18",
						0
					]
				}
			},
			{
				"patchline": {
					"source": [
						"obj-18",
						0
					],
					"destination": [
						"obj-19",
						0
					]
				}
			},
			{
				"patchline": {
					"source": [
						"obj-15",
						1
					],
					"destination": [
						"obj-20",
						0
					]
				}
			},
			{
				"patchline": {
					"source": [
						"obj-20",
						0
					],
					"destination": [
						"obj-21",
						0
					]
				}
			},
			{
				"patchline": {
					"source": [
						"obj-19",
						0
					],
					"destination": [
						"obj-22",
						0
					]
				}
			},
			{
				"patchline": {
					"source": [
						"obj-21",
						0
					],
					"destination": [
						"obj-22",
						1
					]
				}
			},
			{
				"patchline": {
					"source": [
						"obj-14",
						1
					],
					"destination": [
						"obj-23",
						0
					]
				}
			},
			{
				"patchline": {
					"source": [
						"obj-23",
						1
					],
					"destination": [
						"obj-24",
						0
					]
				}
			},
			{
				"patchline": {
					"source": [
						"obj-24",
						0
					],
					"destination": [
						"obj-26",
						1
					]
				}
			},
			{
				"patchline": {
					"source": [
						"obj-25",
						0
					],
					"destination": [
						"obj-26",
						0
					]
				}
			},
			{
				"patchline": {
					"source": [
						"obj-26",
						0
					],
					"destination": [
						"obj-27",
						0
					]
				}
			},
			{
				"patchline": {
					"source": [
						"obj-22",
						0
					],
					"destination": [
						"obj-28",
						0
					]
				}
			},
			{
				"patchline": {
					"source": [
						"obj-27",
						0
					],
					"destination": [
						"obj-28",
						0
					]
				}
			},
			{
				"patchline": {
					"source": [
						"obj-28",
						0
					],
					"destination": [
						"obj-29",
						0
					]
				}
			},
			{
				"patchline": {
					"source": [
						"obj-28",
						0
					],
					"destination": [
						"obj-29",
						1
					]
				}
			},
			{
				"patchline": {
					"source": [
						"obj-3",
						2
					],
					"destination": [
						"obj-31",
						0
					]
				}
			}
		],
		"dependency_cache": [
			{
				"name": "trackosc.parse.js",
				"bootpath": ".",
				"patcherrelativepath": ".",
				"type": "TEXT",
				"implicit": 1
			}
		],
		"autosave": 0
	}
}
