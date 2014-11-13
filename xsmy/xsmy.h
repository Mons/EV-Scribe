#ifndef XSMY_H
#define XSMY_H
#define NEED_my_snprintf
#include "ppport.h"
#include "xsendian.h"
#include <stdio.h>

#ifndef I64
typedef int64_t I64;
#endif

#ifndef U64
typedef uint64_t U64;
#endif

typedef
	union {
		char     *c;
		U32      *i;
		U64      *q;
		U16      *s;
	} uniptr;

#define uptr_sv_size( up, svx, need ) \
	STMT_START {                                                           \
		if ( up.c - SvPVX(svx) + need < SvLEN(svx) )  { \
		} \
		else {\
			STRLEN used = up.c - SvPVX(svx); \
			up.c = sv_grow(svx, SvLEN(svx) + need ); \
			up.c += used; \
		}\
	} STMT_END

#define uptr_sv_check( up, svx, totalneed ) \
	STMT_START {                                                           \
		if ( totalneed < SvLEN(svx) )  { \
		} \
		else {\
			STRLEN used = up.c - SvPVX(svx); \
			up.c = sv_grow(svx, totalneed ); \
			up.c += used; \
		}\
	} STMT_END

#ifdef HAS_QUAD
#define HAS_LL 1
#else
#define HAS_LL 0
#endif

#ifndef cwarn
#define cwarn(fmt, ...)   do{ \
	fprintf(stderr, "[WARN] %s:%d: ", __FILE__, __LINE__); \
	fprintf(stderr, fmt, ##__VA_ARGS__); \
	if (fmt[strlen(fmt) - 1] != 0x0a) { fprintf(stderr, "\n"); } \
	} while(0)
#endif

#ifndef likely
#define likely(x) __builtin_expect((x),1)
#define unlikely(x) __builtin_expect((x),0)
#endif

#define dSVX(sv,ref,type) \
	SV *sv = newSV( sizeof(type) );\
	SvUPGRADE( sv, SVt_PV ); \
	SvCUR_set(sv,sizeof(type)); \
	SvPOKp_on(sv); \
	type * ref = (type *) SvPVX( sv ); \
	memset(ref,0,sizeof(type)); \

#ifndef dObjBy
#define dObjBy(Type,obj,ptr,xx) Type * obj = (Type *) ( (char *) ptr - (ptrdiff_t) &((Type *) 0)-> xx )
#endif

void * safecpy(const void *src,register size_t len) {
	char *new = safemalloc(len);
	memcpy(new,src,len+1);
	new[len]=0;
	return new;
}

#define croak_cb(cb,...) STMT_START {\
		warn(__VA_ARGS__);\
		dSP;\
		ENTER;\
		SAVETMPS;\
		PUSHMARK(SP);\
		EXTEND(SP, 2);\
		PUSHs(&PL_sv_undef);\
		PUSHs( sv_2mortal(newSVpvf(__VA_ARGS__)) );\
		PUTBACK;\
		call_sv( cb, G_DISCARD | G_VOID );\
		FREETMPS;\
		LEAVE;\
		return NULL;\
} STMT_END

#define HEX_SZ (16*10 + 1)
#define CHR_SZ (16*8 + 1)

void xd(char *data, STRLEN size) {
	/* dumps size bytes of *data to stdout. Looks like:
	 * [0000] 75 6E 6B 6E 6F 77 6E 20 30 FF 00 00 00 00 39 00 unknown 0.....9.
	 * src = 16 bytes.
	 * dst = 6       +  16 * 3   +      4*2         +  16       + 1
	 *       prefix    byte+pad    sp between col    visual     newline
	 */
	U8 row  = 16;
	U8 hpad = 1;
	U8 cpad = 0;
	U8 hsp  = 1;
	U8 csp  = 1;
	U8 sp   = 4;
	
	U8 every = (U8)row / sp;
	
	unsigned char *p = data;
	unsigned char c;
	STRLEN n;
	//UV addr;
	//char bytestr[4] = {0};
	char addrstr[10] = {0};
	char hexstr[ HEX_SZ ] = {0};
	char chrstr[ CHR_SZ ] = {0};
	STRLEN hex_sz = row*(2+hpad) + hsp * sp + 1; /* size = bytes<16*2> + 16*<hpad> + col<hsp*sp> */
	STRLEN chr_sz = row*(2+cpad) + csp * sp + 1; /* size = bytes<16> + 16*cpad + col<csp*sp> */
	
	//SV * rv = newSVpvn("",0);
	
	if ( hex_sz > HEX_SZ ) {
		warn("Parameters too big: estimated hex size will be %zu, but have only %zu", hex_sz, (size_t)HEX_SZ);
		return;
	}
	if ( chr_sz > CHR_SZ ) {
		warn("Parameters too big: estimated chr size will be %zu, but have only %zu", chr_sz, (size_t)CHR_SZ);
		return;
	}
	
	//STRLEN sv_sz = ( size + row-1 ) * ( (U8)( 6 + 3 + hex_sz + 2 + chr_sz + 1 + row-1 ) / row );
	/*                      ^ reserve for incomplete string             \n      ^ emulation of ceil */
	//SvGROW(rv,sv_sz);
	
	char *curhex = hexstr;
	char *curchr = chrstr;
	for(n=1; n<=size; n++) {
		if (n % row == 1)
			snprintf(addrstr, sizeof(addrstr), "%04"UVxf, ( PTR2UV(p)-PTR2UV(data) ) & 0xffff );
		
		c = *p;
		if (c < 0x20 || c > 0x7f) {
			c = '.';
		}
		
		/* store hex str (for left side) */
		my_snprintf(curhex, 3+hpad, "%02X%-*s", *p, hpad,""); curhex += 2+hpad;
		
		/* store char str (for right side) */
		my_snprintf(curchr, 2+cpad, "%c%-*s", c, cpad, ""); curchr += 1+cpad;
		
		//warn("n=%d, row=%d, every=%d\n",n,row,every);
		if( n % row == 0 ) {
			/* line completed */
			printf("[%-4.4s]   %s  %s\n", addrstr, hexstr, chrstr);
			//sv_catpvf(rv,"[%-4.4s]   %s  %s\n", addrstr, hexstr, chrstr);
			//sv_catpvf(rv,"[%-4.4s]   %-*s %-*s\n", addrstr, hex_sz-1, hexstr, chr_sz-1, chrstr);
			hexstr[0] = 0; curhex = hexstr;
			chrstr[0] = 0; curchr = chrstr;
		} else if( every && ( n % every == 0 ) ) {
			/* half line: add whitespaces */
			my_snprintf(curhex, 1+hsp, "%-*s", hsp, ""); curhex += hsp;
			my_snprintf(curchr, 1+csp, "%-*s", csp, ""); curchr += csp;
		}
		p++; /* next byte */
	}
	
	if (curhex > hexstr) {
		/* print rest of buffer if not empty */
		printf("[%4.4s]   %s  %s\n", addrstr, hexstr, chrstr);
		//sv_catpvf(rv,"[%-4.4s]   %-*s %-*s\n", addrstr, hex_sz-1, hexstr, chr_sz-1, chrstr);
	}
	//warn("String length: %d, sv_sz=%d",SvCUR(rv),sv_sz);
	return;
}

#endif
