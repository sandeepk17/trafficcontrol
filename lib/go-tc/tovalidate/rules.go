// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at

// http://www.apache.org/licenses/LICENSE-2.0

// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

package tovalidate

import (
	"errors"
	"fmt"
	"net"
	"reflect"
	"regexp"
	"strings"
)

var rxAlphanumericUnderscoreDash = regexp.MustCompile(`^[a-zA-Z0-9\-_]+$`)

// NoSpaces returns true if the string has no spaces
func NoSpaces(str string) bool {
	return !strings.ContainsAny(str, " ")
}

// IsAlphanumericUnderscoreDash returns true if the string consists of only alphanumeric, underscore, or dash characters.
func IsAlphanumericUnderscoreDash(str string) bool {
	return rxAlphanumericUnderscoreDash.MatchString(str)
}

// NoPeriods returns true if the string has no periods
func NoPeriods(str string) bool {
	return !strings.ContainsAny(str, ".")
}

// IsOneOfString generates a validator function returning whether string is in the set of strings
func IsOneOfString(set ...string) func(string) bool {
	return func(s string) bool {
		for _, x := range set {
			if s == x {
				return true
			}
		}
		return false
	}
}

// IsOneOfStringICase is a case-insensitive version of IsOneOfString
func IsOneOfStringICase(set ...string) func(string) bool {
	var lowcased []string
	for _, s := range set {
		lowcased = append(lowcased, strings.ToLower(s))
	}
	return func(s string) bool {
		return IsOneOfString(lowcased...)(strings.ToLower(s))
	}
}

// IsPtrToSliceOfUniqueStringersICase returns a validator function which returns an error if the argument is a non-nil
// pointer to a slice of Stringers whose String() values are not in the set of strings or there are duplicate strings
func IsPtrToSliceOfUniqueStringersICase(set ...string) func(interface{}) error {
	lowcased := make(map[string]bool, len(set))
	for _, s := range set {
		lowcased[strings.ToLower(s)] = true
	}
	return func(slicePtr interface{}) error {

		rv := reflect.ValueOf(slicePtr)
		if rv.Kind() != reflect.Ptr {
			return fmt.Errorf("%T is not a pointer", slicePtr)
		}

		if rv.IsNil() {
			return nil
		}

		slice := rv.Elem()
		if slice.Kind() != reflect.Slice {
			return fmt.Errorf("%T is not a slice", slicePtr)
		}

		seen := make(map[string]bool, len(set))

		l := slice.Len()
		for i := 0; i < l; i++ {
			if item := slice.Index(i).Interface(); item != nil {
				s, ok := item.(fmt.Stringer)
				if !ok {
					return fmt.Errorf("%T is not a pointer to a slice of Stringers", slicePtr)
				}
				lc := strings.ToLower(s.String())
				if !lowcased[lc] {
					return fmt.Errorf("'%s' is not one of %v", lc, set)
				}
				if _, ok := seen[lc]; ok {
					return fmt.Errorf("duplicate value found: '%s'", lc)
				}
				seen[lc] = true
			}
		}
		return nil
	}
}

func IsGreaterThanZero(value interface{}) error {
	switch v := value.(type) {
	case *int:
		if v == nil || *v > 0 {
			return nil
		}
	case *float64:
		if v == nil || *v > 0 {
			return nil
		}
	default:
		return fmt.Errorf("IsGreaterThanZero validation failure: unknown type %T", value)
	}
	return errors.New("must be greater than zero")
}

func IsValidPortNumber(value interface{}) error {
	switch v := value.(type) {
	case *int:
		if v == nil || *v > 0 && *v <= 65535 {
			return nil
		}
	case *float64:
		if v == nil || *v > 0 && *v <= 65535 {
			return nil
		}
	default:
		return fmt.Errorf("IsValidPortNumber validation failure: unknown type %T", value)
	}
	return errors.New("must be a valid port number")
}

func IsValidIPv6CIDROrAddress(value interface{}) error {
	switch v := value.(type) {
	case *string:
		if v == nil {
			return nil
		}
		ip, _, err := net.ParseCIDR(*v)
		if err == nil {
			if ip.To4() == nil {
				return nil
			} else {
				return fmt.Errorf("got IPv4 CIDR, IPv6 expected")
			}
		} else {
			ip := net.ParseIP(*v)
			if ip != nil {
				if ip.To4() == nil {
					return nil
				} else {
					return fmt.Errorf("got IPv4 address, IPv6 expected")
				}
			}
		}
		return fmt.Errorf("unable to parse an IPv6 address or CIDR from: %s", *v)
	default:
		return fmt.Errorf("IsValidIPv6CIDROrAddress validation failure: unknown type %T", value)
	}
}
