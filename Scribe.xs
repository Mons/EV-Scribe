#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#define NEED_sv_2pv_flags_GLOBAL
#include "ppport.h"

#include "xsmy.h"

#include "EVAPI.h"
#define XSEV_CON_HOOKS 1
#include "xsevcnn.h"


static const int VERSION_1    = 0x80010000;
#define VERSION_MASK 0xffff0000

#ifndef WBUF_MAX
#  define WBUF_MAX 10240
#endif

enum TType {
  T_STOP       = 0,
  T_VOID       = 1,
  T_BOOL       = 2,
  T_BYTE       = 3,
  T_I08        = 3,
  T_I16        = 6,
  T_I32        = 8,
  T_U64        = 9,
  T_I64        = 10,
  T_DOUBLE     = 4,
  T_STRING     = 11,
  T_UTF7       = 11,
  T_STRUCT     = 12,
  T_MAP        = 13,
  T_SET        = 14,
  T_LIST       = 15,
  T_UTF8       = 16,
  T_UTF16      = 17
};

//typedef struct ScCnn;
typedef struct {
	xs_ev_cnn_struct;
	
	void (*on_disconnect_before)(void *, int);
	void (*on_disconnect_after)(void *, int);
	void (*on_connect_before)(void *, struct sockaddr *);
	void (*on_connect_after)(void *, struct sockaddr *);
	
	uint32_t pending;
	uint32_t seq;
	HV      *reqs;
	size_t   wbuf_limit;
} ScCnn;

typedef struct {
	SV   * cb;
	SV   * wbuf;
	char * call;
} ScCtx;

#pragma pack (push, 1)
typedef struct {
	unsigned size : 32;
	char     v0   : 8;
	char     v1   : 8;
	char     t0   : 8;
	char     t1   : 8;
	//unsigned type : 16;
	
	//unsigned len  : 32;
	union {
		char     c[4];
		unsigned i : 32;
	} len;
	union {
		char     c[3];
		unsigned i:24;
	} proc;
	unsigned seq  : 32;
	struct {
		unsigned char type;
		unsigned char  id[2];
	} field;
	struct {
		unsigned char type;
		unsigned int  size : 32;
	} list;
} sc_hdr_t;
#pragma pack (pop)

static const sc_hdr_t default_hdr = {
	0,
	0x80,0x01, // version
	0,1, //type
	
	{0,0,0,3},
	{'L','o','g'},
	0xdeadbeef,
	{ 15,{0,1} },
	{ 12,0 }
};


static void on_read(ev_cnn * self, size_t len) {
	register uniptr p;
	
	ENTER;
	SAVETMPS;
	//cwarn("remember stack sp = %d",PL_stack_sp - PL_stack_base);
	//SV **sp1 = PL_stack_sp;
	
	do_disable_rw_timer(self);
	
	ScCnn * sc = (ScCnn *) self;
	p.c = self->rbuf;
	char *end = p.c + self->ruse;
	char *next;
	
	SV *key;
	ScCtx * ctx;
	
	dSP;
	
	//warn("Read %u",self->ruse);
	//xd(self->rbuf,self->ruse);
	
	while ( p.c < end ) {
		if (unlikely( p.c + 4 > end )) break;
		unsigned pklen = be32toh( *p.i );
		if (unlikely( p.c + 4 + pklen > end )) break;
		p.i++;
		
		next = p.c + pklen;
		
		self->ruse -= pklen+4;
		//warn("process packet of length %u", pklen);
		
		uint32_t id;
		unsigned version = be32toh( *p.i++ );
		unsigned char type;
		if ( (version & VERSION_MASK ) > 0) {
			if ( ( version & VERSION_MASK ) != VERSION_1 ) {
				warn("Bad version received: %u",version);
				p.c = next;
				continue;
			}
			type = version & 0xff;
			unsigned length = be32toh( *p.i++ );
			p.c += length; // skip string
			id = be32toh( *p.i++ );
			
			
		} else { // old packet format
			// version is actually string length
			p.c += version; // skip string
			type = (unsigned char) *p.c++;
			id   = be32toh( *p.i++ );
		}
		
		if (type == 3) {
			//TODO: read exception struct
		}
		
		p.c = next;
		key = hv_delete(sc->reqs, (char *) &id, sizeof(id),0);
		
		if (unlikely(!key)) {
			cwarn("key %d not found",id);
			continue;
		} else {
			ctx = ( ScCtx * ) SvPVX( key );
			SvREFCNT_dec(ctx->wbuf);
			
			if (ctx->cb) {
					//cwarn("read sp in  = %p (%d)",sp, PL_stack_sp - PL_stack_base);
					
					SPAGAIN;
					ENTER; SAVETMPS;
					
					if (type == 2) {
						PUSHMARK(SP);
						EXTEND(SP, 1);
						PUSHs( sv_2mortal(newSVuv(1)) );
						PUTBACK;
					}
					else { // 3
						PUSHMARK(SP);
						EXTEND(SP, 2);
						PUSHs( &PL_sv_undef );
						PUSHs( sv_2mortal(newSVpvf("Exception received")) );
						PUTBACK;
						
					}
					(void) call_sv( ctx->cb, G_DISCARD | G_VOID );
					
					//SPAGAIN;PUTBACK;
					
					SvREFCNT_dec(ctx->cb);
					
					FREETMPS; LEAVE;
			}
			--sc->pending;
		}
	}
	self->ruse = end - p.c;
	if (unlikely(self->ruse > 0)) {
		memmove(self->rbuf,p.c,self->ruse);
	}
	
	FREETMPS;
	LEAVE;
}

#ifndef MSG_CAT_DEFAULT_SIZE
#define MSG_CAT_DEFAULT_SIZE 10
#endif
#ifndef MSG_MSG_DEFAULT_SIZE
#define MSG_MSG_DEFAULT_SIZE 128
#endif

#define MSG_ALL_DEFAULT_SIZE (MSG_CAT_DEFAULT_SIZE+MSG_MSG_DEFAULT_SIZE)

static inline SV * pkt_log( ScCtx *ctx, uint32_t iid, AV * messages, SV *cb ) {
	register uniptr p;
	// N N/a* N : 12+3=15
	// Cn CN : 8 (23)
	// av_len * ( Cn N/a* + Cn N/a* + x = 7 + catlen + 7 + msglen + 1 )
	/*
		header +
		count * (
			cat: c + s + i + content
			msg: c + s + i + content
		)
		+ 1
	*/
	
	//croak_cb(cb,"xxx");
	
	int msgcount = ( av_len(messages)+1 );
	STRLEN const_len, var_len;
	const_len =
		sizeof( sc_hdr_t ) +
		msgcount * (
			1 + 2 + 4 +
			1 + 2 + 4 +
			1 // trailing 0
		)
		+1 //trailing 0
	;
	var_len = MSG_ALL_DEFAULT_SIZE * msgcount;  // to avoid reallocation we request + MGS_ALL_DEFAULT_SIZE * msgcount because messages will not be empty
	
	SV *rv = sv_2mortal(newSV(
		const_len +  var_len
	));
	SvUPGRADE( rv, SVt_PV );
	//SvPOK_on(rv); need only for debug
	
	sc_hdr_t *h = (sc_hdr_t *) SvPVX(rv);
	
	memcpy( h, &default_hdr, sizeof( sc_hdr_t ));
	
	p.c = (char *)(h+1);
		
	char *pvx;
	STRLEN len;
	int k;
	for (k=0; k <= av_len(messages); k++) {
		SV *f = *av_fetch( messages, k, 0 );
		if ( unlikely(!SvROK(f)) ) {
			var_len -= MSG_ALL_DEFAULT_SIZE; // free reserved var
		} else {
			//TODO: check type
			HV *ent = (HV *)SvRV(f);
			SV **cat = hv_fetchs(ent, "category",0);
			SV **msg = hv_fetchs(ent, "message",0);
			if (cat && *cat && SvOK(*cat)) {
				pvx = SvPV(*cat,len);
				var_len += len - MSG_CAT_DEFAULT_SIZE;
				uptr_sv_check( p, rv, const_len + var_len );
				
				*(p.c++) = T_STRING;
				*(p.s++) = htobe16(1);
				*(p.i++) = htobe32( len );
				memcpy(p.c, pvx, len);
				p.c += len;
			} else {
				var_len -= MSG_CAT_DEFAULT_SIZE; // free reserved var
			}
			if (msg && *msg && SvOK(*msg)) {
				if (!SvROK(*msg)) {
					pvx = SvPV(*msg,len);
				} else {
					pvx = SvPV(SvRV(*msg), len);
				}
				var_len += len - MSG_CAT_DEFAULT_SIZE;
				uptr_sv_check( p, rv, const_len + var_len );
				
				*(p.c++) = T_STRING;
				*(p.s++) = htobe16(2);
				*(p.i++) = htobe32( len );
				memcpy(p.c, pvx, len);
				p.c += len;
			} else {
				var_len -= MSG_MSG_DEFAULT_SIZE; // free reserved var
			}
			*(p.c++) = 0;
		}
	}
	*(p.c++) = 0;
	
	SvCUR_set( rv, p.c - SvPVX(rv) );
	
	
	h = (sc_hdr_t *) SvPVX( rv ); // for sure
	h->size   = htobe32( SvCUR(rv) - 4 );
	h->seq    = htobe32( iid );
	h->list.size = htobe32( msgcount );
	
	//xd( SvPVX(rv), p.c - SvPVX(rv) );
	
	return SvREFCNT_inc(rv);
}

void free_reqs (ScCnn *self, const char * message) {
	if (unlikely(!self->reqs)) return;
	
	ENTER;SAVETMPS;
	
	dSP;
	
	HE *ent;
	(void) hv_iterinit( self->reqs );
	while ((ent = hv_iternext( self->reqs ))) {
		ScCtx * ctx = (ScCtx *) SvPVX( HeVAL(ent) );
		SvREFCNT_dec(ctx->wbuf);
		
		if (ctx->cb) {
			SPAGAIN;
			ENTER; SAVETMPS;
			
			PUSHMARK(SP);
			EXTEND(SP, 2);
			PUSHs( &PL_sv_undef );
			PUSHs( sv_2mortal(newSVpvf(message)) );
			PUTBACK;
			
			(void) call_sv( ctx->cb, G_DISCARD | G_VOID );
			
			//SPAGAIN;PUTBACK;
			
			SvREFCNT_dec(ctx->cb);
		
			FREETMPS; LEAVE;
		}
		
		--self->pending;
	}
	
	hv_clear(self->reqs);
	
	FREETMPS;LEAVE;
}

static void on_disconnect (ScCnn * self, int err) {
	ENTER;SAVETMPS;
	
	//warn("disconnect: %s", strerror(err));
	if (err == 0) {
		free_reqs(self, "Connection closed");
	} else {
		SV *msg = sv_2mortal(newSVpvf("Disconnected: %s",strerror(err)));
		free_reqs(self, SvPVX(msg));
	}
	
	FREETMPS;LEAVE;
}

MODULE = EV::Scribe		PACKAGE = EV::Scribe
PROTOTYPES: DISABLE
BOOT:
{
	I_EV_API ("EV::Scribe");
	I_EV_CNN_API("EV::Scribe" );
}

void new(SV *pk, HV *conf)
	PPCODE:
		if (0) pk = pk;
		xs_ev_cnn_new(ScCnn);
		self->cnn.on_read = (c_cb_read_t) on_read;
		self->on_disconnect_before = ( void (*)(void *,int) ) on_disconnect;
		SV **key;
		if ((key = hv_fetchs(conf, "wbuf_limit", 0))) {
			if (SvOK(*key)) {
				IV wbuf_limit = SvIV(*key);
				self->wbuf_limit = wbuf_limit > 0 ? wbuf_limit : 0;
			} else {
				self->wbuf_limit = WBUF_MAX;
			}
		}
		if ((key = hv_fetchs(conf, "write_immediately", 0)) && SvOK(*key)) {
			self->cnn.wnow = SvTRUE(*key) ? 1 : 0;
		} else {
			self->cnn.wnow = 0;
		}
		self->reqs = newHV();
		
		XSRETURN(1);

void DESTROY(SV *this)
	PPCODE:
		if (0) this = this;
		xs_ev_cnn_self(ScCnn);
		
		if (!PL_dirty && self->reqs) {
			//TODO
			free_reqs(self, "Destroyed");
			SvREFCNT_dec(self->reqs);
			self->reqs = 0;
		}
		xs_ev_cnn_destroy(self);

void log (SV *this, AV * messages,  SV * cb)
	PPCODE:
		if (0) this = this;
		xs_ev_cnn_self(ScCnn);
		xs_ev_cnn_checkconn_wlimit(self,cb,self->wbuf_limit);
		
		dSVX(ctxsv, ctx, ScCtx);
		sv_2mortal(ctxsv);
		ctx->call = "logx";
		
		uint32_t iid = ++self->seq;
		
		if ((ctx->wbuf = pkt_log(ctx, iid, messages, cb ))) {
			SvREFCNT_inc(ctx->cb = cb);
			
			(void) hv_store( self->reqs, (char*)&iid, sizeof(iid), SvREFCNT_inc(ctxsv), 0 );
			
			++self->pending;
			
			do_write( &self->cnn,SvPVX(ctx->wbuf), SvCUR(ctx->wbuf));
			
			XSRETURN_UNDEF;
			
		} else {
			warn( "shit" );
			XSRETURN_UNDEF;
		}
