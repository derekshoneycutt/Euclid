import './style.scss';

import { EUCLID_DATA } from './data';
import { Imogene as $_ } from '../Imogene/Imogene';

import {MDCRipple} from '@material/ripple';
import showdown from 'showdown';
import DOMPurify from 'dompurify';

function cleanPath(path) {
    return path;//.replace('/build/dist', '/Euclid');
}
function reverseCleanPath(path) {
    return path//;.replace('/Euclid', '/build/dist');
}

function getMatchingPage(searchBy, obj) {
    if (obj.page === searchBy) {
        return obj;
    }
    else if ('children' in obj) {
        return obj.children.reduce((prev, curr, index) => {
            if (prev != null)
                return prev;
            let tryMatch = getMatchingPage(searchBy, curr);
            if (tryMatch !== null)
                return tryMatch;
            return null;
        }, null);
    }
    return null;
}

function matchingPageFromBook(searchBy, curr) {
    let match = getMatchingPage(searchBy, curr);
    if (match !== null)
        return match;
    match = getMatchingPage(searchBy, curr.definitions);
    if (match !== null)
        return match;
    match = getMatchingPage(searchBy, curr.common_notions);
    if (match !== null)
        return match;
    match = getMatchingPage(searchBy, curr.postulates);
    if (match !== null)
        return match;
    match = getMatchingPage(searchBy, curr.added_axioms);
    if (match !== null)
        return match;
    match = getMatchingPage(searchBy, curr.propositions);
    if (match !== null)
        return match;

    return null;
}

function findMatchingPage(searchBy) {
    if (searchBy === EUCLID_DATA.page) {
        return EUCLID_DATA;
    }

    let match = EUCLID_DATA.books.reduce((prev, curr, index) => {
        if (prev !== null)
            return prev;
        return matchingPageFromBook(searchBy, curr);
    }, null);

    return match;
}

function breadcrumbPage(forPage, obj) {
    if (obj.page === forPage) {
        return [obj];
    }
    else if ('children' in obj) {
        return obj.children.reduce((arr, child) => {
            if (arr.length > 0)
                return arr;

            let newCrumbs = breadcrumbPage(forPage, child);
            if (newCrumbs.length > 0)
                return [obj, ...newCrumbs];
            return [];
        }, []);
    }
    return [];
}

function breadcrumb(forPage) {
    return EUCLID_DATA.books.reduce((arr, book) => {
        if (arr.length > 1)
            return arr;

        if (book.page === forPage) {
            arr.push(book);
        }
        else {
            let crumbs = breadcrumbPage(forPage, book.definitions)
            if (crumbs.length > 0) {
                arr.push(book, ...crumbs);
                return arr;
            }
            crumbs = breadcrumbPage(forPage, book.postulates)
            if (crumbs.length > 0) {
                arr.push(book, ...crumbs);
                return arr;
            }
            crumbs = breadcrumbPage(forPage, book.common_notions)
            if (crumbs.length > 0) {
                arr.push(book, ...crumbs);
                return arr;
            }
            crumbs = breadcrumbPage(forPage, book.propositions)
            if (crumbs.length > 0) {
                arr.push(book, ...crumbs);
                return arr;
            }
            crumbs = breadcrumbPage(forPage, book.added_axioms)
            if (crumbs.length > 0) {
                arr.push(book, ...crumbs);
                return arr;
            }
        }
        return arr;
    }, [EUCLID_DATA]);
}


function tryLoadPage() {
    let currentPage = cleanPath(`${window.location.pathname}`);
    if (currentPage.slice(-1) === '/') {
        currentPage = currentPage + "index.html"
    }
    let page = findMatchingPage(currentPage);

    let article = $_.find("#main-article");

    let text = `# ${page.title}\n\n${page.head}`;
    if (page.animation2d)
    {
        text = `${text}\n\n## 2D Animation\n\n![${page.title} 2D](${page.animation2d})`
    }
    if (page.animation3d)
    {
        text = `${text}\n\n## 3D Animation\n\n![${page.title} 3D](${page.animation3d})`
    }
    const html = DOMPurify.sanitize(new showdown.Converter().makeHtml(text));
    article.empty();
    article.setProperties({ innerHTML: html });
}

function generateSideBarListFrom(obj, currentPage, num) {
    let hasChildren = ('children' in obj);
    let matchPage = getMatchingPage(currentPage, obj);
    let listItem = $_.make('li', {
        class: `${matchPage === null || matchPage === undefined ? 'collapsed' : 'on_page'} ${hasChildren ? "with_children" : "no_children"}`
    });
    let linkHref = reverseCleanPath(obj.page);
    let linkElement = $_.make('a', { href: matchPage === obj ? undefined : linkHref, class: 'nav_link' }, `${num ? num + '. ' : ''}${obj.title}`);

    obj.link_element = linkElement;
    obj.listitem_element = listItem;

    if (hasChildren) {
        linkElement.emptyAndReplace($_.make('span', {
            class: "material-symbols-outlined collapse-marker",
            innerHTML: "expand_more",
            on: {
                click: e => {
                    listItem.setClassList({ collapsed: !listItem[0].classList.contains('collapsed') });
                }
            }
        }), obj.title);
        listItem.appendChildren(
            linkElement);

        let subList = $_.make('ol', { class: 'nav-ord-list' },
                                ...(obj.children.map((child, index) => generateSideBarListFrom(child, currentPage, index + 1))));
        listItem.appendChildren(subList);
        obj.sublist_element = subList;
    }
    else {
        listItem.appendChildren(linkElement);
    }

    return listItem;
}

function loadSideBar() {
    let currentPage = cleanPath(`${window.location.pathname}`);
    if (currentPage.slice(-1) === '/') {
        currentPage = currentPage + "index.html"
    }

    let navlist = $_.find('#side-navlist');

    navlist.empty();

    navlist.appendChildren(
        $_.make('li', { class: `home_item ${currentPage === EUCLID_DATA.page ? 'on_page' : ''}` },
                ['a',
                    {
                        href: currentPage === EUCLID_DATA.page ? undefined : reverseCleanPath(EUCLID_DATA.page),
                        class: 'nav_link'
                    },
                    ['span', { class: 'material-symbols-outlined home_icon' }, 'home'],
                    EUCLID_DATA.title]));


    EUCLID_DATA.books.forEach(book => {
        let matchPage = matchingPageFromBook(currentPage, book);

        let childEl = $_.make('li', { class: matchPage === null || matchPage === undefined ? "collapsed" : 'on_page' });
        let linkElement = $_.make('a',
                                    {
                                        href: matchPage === book ? undefined : reverseCleanPath(book.page),
                                        class: 'nav_link'
                                    },
                                    book.title);
        let subList = $_.make('ul', { class: 'nav-hier-list' },
                                generateSideBarListFrom(book.definitions, currentPage),
                                generateSideBarListFrom(book.postulates, currentPage),
                                generateSideBarListFrom(book.common_notions, currentPage),
                                generateSideBarListFrom(book.propositions, currentPage),
                                generateSideBarListFrom(book.added_axioms, currentPage));
        linkElement.emptyAndReplace(
            $_.make('span',
                {
                    class: "material-symbols-outlined collapse-marker",
                    innerHTML: "expand_more",
                    on: {
                        click: e => {
                            childEl.setClassList({ collapsed: !childEl[0].classList.contains('collapsed') });
                        }
                    }
                }), book.title);
        childEl.appendChildren(
            linkElement,
            subList);
        navlist.appendChildren(childEl);

        book.link_element = linkElement;
        book.listitem_element = childEl;
        book.sublist_element = subList;
    });
}

function refreshPageSelection(obj, currentPage) {
    let matchPage = getMatchingPage(cleanPath(currentPage), obj);
    obj.listitem_element.setClassList({
        on_page: !!matchPage,
        collapsed: matchPage !== obj && obj.listitem_element[0].classList.contains('collapsed')
    });
    obj.link_element.setProperties({ href: matchPage === obj ? undefined : reverseCleanPath(obj.page)});

    if ('children' in obj) {
        obj.children.forEach(child => refreshPageSelection(child, currentPage));
    }
}

function updateBreadcrumbs(pathname) {
    let crumbs = breadcrumb(cleanPath(pathname));
    let crumbsList = $_.find('ol#breadcrumb-list');
    crumbsList.emptyAndReplace(...(crumbs.map(crumb => $_.make('li', ['a', { href: reverseCleanPath(crumb.page) }, crumb.title]))));
}

function refreshTheView(pathname) {
    tryLoadPage();

    let home_item = $_.find('.home_item');
    let home_link = home_item.find('a');
    home_item.setClassList({ on_page: (cleanPath(pathname) === EUCLID_DATA.page) });
    home_link.setProperties({ href: cleanPath(pathname) === EUCLID_DATA.page? undefined : reverseCleanPath(EUCLID_DATA.page)});
    EUCLID_DATA.books.forEach(book => {
        let matchPage = matchingPageFromBook(cleanPath(pathname), book);
        book.listitem_element.setClassList({
            on_page: !!matchPage,
            collapsed: matchPage !== book && book.listitem_element[0].classList.contains('collapsed')
        });
        book.link_element.setProperties({ href: matchPage === book ? undefined : reverseCleanPath(book.page)});

        refreshPageSelection(book.definitions, pathname);
        refreshPageSelection(book.postulates, pathname);
        refreshPageSelection(book.common_notions, pathname);
        refreshPageSelection(book.propositions, pathname);
        refreshPageSelection(book.added_axioms, pathname);
    });

    // Load breadcrumbs
    updateBreadcrumbs(pathname);
}

$_.runOnLoad(() => {
    loadSideBar();

    tryLoadPage();


    updateBreadcrumbs(cleanPath(window.location.pathname));

    document.addEventListener("click", e => {
        let link = e.target.closest('a');
        if (link) {
            let pathname = cleanPath(link.pathname);
            if (pathname === '' || pathname === undefined || pathname === null) {
                pathname = cleanPath(window.location.pathname);
                let match = findMatchingPage(pathname);
                if (match) {
                    match.listitem_element.setClassList({
                        collapsed: !match.listitem_element[0].classList.contains('collapsed')
                    });
                }
            }
            else {
                let match = findMatchingPage(pathname);
                if (match !== null && match !== undefined) {
                    e.preventDefault();

                    history.pushState({ from: `${window.location.pathname}`, to: `${pathname}` }, "", link.pathname);

                    refreshTheView(link.pathname);
                }
            }
        }
    });

    window.addEventListener("popstate", e => {
        e.preventDefault();
        refreshTheView(window.location.pathname);
    });

    let sidebar = $_.find('#sidebar');
    let sidebarCollapser = $_.find('#sidebar-collapser');
    sidebarCollapser.ripple = new MDCRipple(sidebarCollapser[0]);
    sidebarCollapser.addEvents({
        click: e => {
            sidebar.setClassList({ collapsed: !sidebar[0].classList.contains('collapsed') });
        }
    });

    const portrait = window.matchMedia("(orientation: portrait)").matches;
    sidebar.setClassList({ collapsed: portrait });
});
